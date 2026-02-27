import Foundation

final class VirtualGamepad {
    private var device: IOHIDUserDeviceRef?

    init?() {
        // HID descriptor for a simple gamepad with 10 buttons
        let descriptor: [UInt8] = [
            0x05, 0x01,       // Usage Page (Generic Desktop)
            0x09, 0x05,       // Usage (Gamepad)
            0xA1, 0x01,       // Collection (Application)
            0x05, 0x09,       //  Usage Page (Button)
            0x19, 0x01,       //  Usage Min (1)
            0x29, 0x0A,       //  Usage Max (10)
            0x15, 0x00,       //  Logical Min (0)
            0x25, 0x01,       //  Logical Max (1)
            0x95, 0x0A,       //  Report Count (10 buttons)
            0x75, 0x01,       //  Report Size (1 bit)
            0x81, 0x02,       //  Input (Data,Var,Abs)
            0x95, 0x01,       //  Report Count (1) padding
            0x75, 0x06,       //  Report Size (6 bits)
            0x81, 0x03,       //  Input (Const,Var,Abs) padding
            0xC0              // End Collection
        ]

        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey: Data(descriptor),
            kIOHIDProductKey: "Wiimote Virtual Gamepad",
            kIOHIDVendorIDKey: 0x1234,
            kIOHIDProductIDKey: 0x0001
        ]

        guard let dev = IOHIDUserDeviceCreate(kCFAllocatorDefault,
                                              properties as CFDictionary) else {
            print("⚠️  IOHIDUserDeviceCreate returned nil")
            return nil
        }

        self.device = dev
        print("✅ Device created and activated")
    }

    /// `mask` is a 10-bit bitfield: bit0 = button1, bit1 = button2, ...
    func sendButtonMask(_ mask: UInt16) {
        guard let device = device else { return }
        var report = mask
        withUnsafeBytes(of: &report) { buffer in
            guard let ptr = buffer.baseAddress else { return }
            let timestamp = mach_absolute_time()
            IOHIDUserDeviceHandleReportWithTimeStamp(device,
                                                     timestamp,
                                                     ptr.assumingMemoryBound(to: UInt8.self),
                                                     buffer.count)
        }
    }
}
