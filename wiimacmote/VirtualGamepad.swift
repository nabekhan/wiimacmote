import Foundation
import Darwin
import IOKit
import IOKit.hid

enum VirtualGamepadCreationError: LocalizedError {
    case deviceCreationFailed
    case initialReportFailed(IOReturn)

    var errorDescription: String? {
        switch self {
        case .deviceCreationFailed:
            return "macOS did not create the virtual HID device. Current macOS releases normally require Apple's restricted virtual-HID entitlement."
        case .initialReportFailed(let code):
            return "The virtual HID device was created but rejected its first report (\(Self.hex(code)))."
        }
    }

    private static func hex(_ value: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: value))
    }
}

/// Keeps the CF object alive until IOKit runs its asynchronous cancel handler.
/// The cancel handler clears `device`, breaking the temporary retain cycle.
private final class VirtualDeviceLifetime {
    var device: IOHIDUserDevice?

    init(device: IOHIDUserDevice) {
        self.device = device
    }
}

/// Experimental virtual HID output for software that consumes generic HID
/// gamepads. macOS does not provide a generally available, supported virtual
/// Game Controller API, so individual games may ignore this device even when
/// raw HID tools can see it.
final class VirtualGamepad {
    let playerIndex: Int

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private var device: IOHIDUserDevice?
    private var lifetime: VirtualDeviceLifetime?
    private var lastState = VirtualGamepadState.neutral
    private var hasSentState = false

    init(playerIndex: Int) throws {
        self.playerIndex = playerIndex
        self.queue = DispatchQueue(
            label: "dev.wiimacmote.virtual-gamepad.p\(playerIndex)",
            qos: .userInteractive
        )
        queue.setSpecific(key: queueKey, value: ())

        let descriptor: [UInt8] = [
            0x05, 0x01,        // Usage Page (Generic Desktop)
            0x09, 0x05,        // Usage (Game Pad)
            0xA1, 0x01,        // Collection (Application)

            // Four signed 8-bit axes: left X/Y and right X/Y.
            0x09, 0x01,        //   Usage (Pointer)
            0xA1, 0x00,        //   Collection (Physical)
            0x09, 0x30,        //     Usage (X)
            0x09, 0x31,        //     Usage (Y)
            0x09, 0x32,        //     Usage (Z)
            0x09, 0x35,        //     Usage (Rz)
            0x15, 0x81,        //     Logical Minimum (-127)
            0x25, 0x7F,        //     Logical Maximum (127)
            0x75, 0x08,        //     Report Size (8)
            0x95, 0x04,        //     Report Count (4)
            0x81, 0x02,        //     Input (Data, Variable, Absolute)
            0xC0,              //   End Collection

            // Hat switch, with 8 as the null/released value.
            0x09, 0x39,        //   Usage (Hat Switch)
            0x15, 0x00,        //   Logical Minimum (0)
            0x25, 0x07,        //   Logical Maximum (7)
            0x35, 0x00,        //   Physical Minimum (0)
            0x46, 0x3B, 0x01,  //   Physical Maximum (315)
            0x65, 0x14,        //   Unit (degrees)
            0x75, 0x04,        //   Report Size (4)
            0x95, 0x01,        //   Report Count (1)
            0x81, 0x42,        //   Input (Data, Variable, Absolute, Null)

            // Sixteen ordinary buttons.
            0x05, 0x09,        //   Usage Page (Button)
            0x19, 0x01,        //   Usage Minimum (Button 1)
            0x29, 0x10,        //   Usage Maximum (Button 16)
            0x15, 0x00,        //   Logical Minimum (0)
            0x25, 0x01,        //   Logical Maximum (1)
            0x75, 0x01,        //   Report Size (1)
            0x95, 0x10,        //   Report Count (16)
            0x81, 0x02,        //   Input (Data, Variable, Absolute)

            // 32 axis bits + 4 hat bits + 16 button bits = 52 bits.
            // Pad to an 8-byte input report.
            0x75, 0x01,        //   Report Size (1)
            0x95, 0x0C,        //   Report Count (12)
            0x81, 0x03,        //   Input (Constant, Variable, Absolute)
            0xC0               // End Collection
        ]

        // These identifiers are deliberately local and generic; the device no
        // longer impersonates Microsoft's Xbox 360 hardware.
        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey as String: Data(descriptor),
            kIOHIDProductKey as String: "WiiMacMote Virtual Gamepad P\(playerIndex)",
            kIOHIDManufacturerKey as String: "WiiMacMote",
            kIOHIDSerialNumberKey as String: "WMM-VIRTUAL-P\(playerIndex)",
            kIOHIDVendorIDKey as String: NSNumber(value: 0x574D), // "WM"
            kIOHIDProductIDKey as String: NSNumber(value: 0x0200 + playerIndex),
            kIOHIDVersionNumberKey as String: NSNumber(value: 0x0200),
            kIOHIDTransportKey as String: "Virtual",
            kIOHIDPrimaryUsagePageKey as String: NSNumber(value: 0x01),
            kIOHIDPrimaryUsageKey as String: NSNumber(value: 0x05)
        ]

        guard let created = IOHIDUserDeviceCreateWithProperties(
            kCFAllocatorDefault,
            properties as CFDictionary,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) else {
            throw VirtualGamepadCreationError.deviceCreationFailed
        }

        let lifetime = VirtualDeviceLifetime(device: created)
        self.device = created
        self.lifetime = lifetime

        IOHIDUserDeviceSetDispatchQueue(created, queue)
        IOHIDUserDeviceSetCancelHandler(created) { [lifetime] in
            lifetime.device = nil
        }
        IOHIDUserDeviceActivate(created)

        let initialResult = Self.submit(.neutral, to: created)
        guard initialResult == kIOReturnSuccess else {
            self.device = nil
            IOHIDUserDeviceCancel(created)
            throw VirtualGamepadCreationError.initialReportFailed(initialResult)
        }
        hasSentState = true
    }

    deinit {
        guard let device else { return }

        let sendNeutral = {
            _ = Self.submit(.neutral, to: device)
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            sendNeutral()
        } else {
            queue.sync(execute: sendNeutral)
        }

        self.device = nil
        IOHIDUserDeviceCancel(device)
    }

    func update(_ state: VirtualGamepadState) {
        enqueue(state, force: false, synchronously: false)
    }

    func reset() {
        enqueue(.neutral, force: true, synchronously: true)
    }

    private func enqueue(
        _ state: VirtualGamepadState,
        force: Bool,
        synchronously: Bool
    ) {
        let operation = { [weak self] in
            guard let self, let device = self.device else { return }
            guard force || !self.hasSentState || state != self.lastState else { return }

            let result = Self.submit(state, to: device)
            if result == kIOReturnSuccess {
                self.lastState = state
                self.hasSentState = true
            }
        }

        if synchronously {
            if DispatchQueue.getSpecific(key: queueKey) != nil {
                operation()
            } else {
                queue.sync(execute: operation)
            }
        } else {
            queue.async(execute: operation)
        }
    }

    private static func submit(
        _ state: VirtualGamepadState,
        to device: IOHIDUserDevice
    ) -> IOReturn {
        var report = makeReport(from: state)
        return report.withUnsafeBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.baseAddress else {
                return kIOReturnBadArgument
            }
            return IOHIDUserDeviceHandleReportWithTimeStamp(
                device,
                mach_absolute_time(),
                baseAddress.assumingMemoryBound(to: UInt8.self),
                report.count
            )
        }
    }

    private static func makeReport(from state: VirtualGamepadState) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 8)
        report[0] = UInt8(bitPattern: state.leftX)
        report[1] = UInt8(bitPattern: state.leftY)
        report[2] = UInt8(bitPattern: state.rightX)
        report[3] = UInt8(bitPattern: state.rightY)

        let buttons = state.buttons
        report[4] = (state.hat & 0x0F) | (UInt8(buttons & 0x000F) << 4)
        report[5] = UInt8((buttons >> 4) & 0x00FF)
        report[6] = UInt8((buttons >> 12) & 0x000F)
        return report
    }
}
