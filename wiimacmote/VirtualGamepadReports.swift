import Foundation

enum VirtualGamepadIdentity: String, CaseIterable, Identifiable, Codable, Sendable {
    case generic
    case xboxSeries
    case switchProSimple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generic: return "Generic HID Gamepad"
        case .xboxSeries: return "Xbox Wireless Controller (Series)"
        case .switchProSimple: return "Switch Pro Controller (simple mode)"
        }
    }

    var shortTitle: String {
        switch self {
        case .generic: return "Generic HID"
        case .xboxSeries: return "Xbox Series"
        case .switchProSimple: return "Switch Pro"
        }
    }

    var detail: String {
        switch self {
        case .generic:
            return "Truthful WiiMacMote identity. Best for raw HID testing, but Game Controller clients may ignore it."
        case .xboxSeries:
            return "Higher-risk compatibility experiment using Xbox Series Bluetooth metadata, a 17-byte native report, and a companion GIP-style stream."
        case .switchProSimple:
            return "Nintendo-like identity using report 0x3F. Full Switch subcommand handshake, motion, and HD rumble are not implemented yet."
        }
    }

    var isRecommended: Bool { self == .xboxSeries }
    var isHardwareImpersonation: Bool { self != .generic }
}

enum VirtualGamepadBackendPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case ioHIDUserDevice
    case coreHID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic (IOHIDUserDevice first)"
        case .ioHIDUserDevice: return "IOHIDUserDevice"
        case .coreHID: return "CoreHID (macOS 15+)"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Tries the established IOKit publisher first, then CoreHID when available."
        case .ioHIDUserDevice:
            return "Uses the IOKit user-space virtual HID publisher available on older macOS releases."
        case .coreHID:
            return "Uses HIDVirtualDevice from CoreHID. Requires macOS 15 or newer and the same restricted entitlement."
        }
    }
}

enum VirtualGamepadBackendKind: String, Codable, Sendable {
    case ioHIDUserDevice = "IOHIDUserDevice"
    case coreHID = "CoreHID"
}

struct VirtualGamepadSpecification: Sendable {
    let identity: VirtualGamepadIdentity
    let descriptor: [UInt8]
    let vendorID: UInt16
    let productID: UInt16
    let productName: String
    let manufacturer: String
    let versionNumber: UInt16
    let ioKitTransport: String
    let serialNumber: String
}

enum VirtualGamepadReports {
    static func specification(
        for identity: VirtualGamepadIdentity,
        playerIndex: Int
    ) -> VirtualGamepadSpecification {
        let player = min(max(playerIndex, 1), 4)
        switch identity {
        case .generic:
            return VirtualGamepadSpecification(
                identity: identity,
                descriptor: genericDescriptor,
                vendorID: 0x574D,
                productID: UInt16(0x0200 + player),
                productName: "WiiMacMote Virtual Gamepad P\(player)",
                manufacturer: "WiiMacMote",
                versionNumber: 0x0205,
                ioKitTransport: "Virtual",
                serialNumber: "WMM-GENERIC-P\(player)"
            )
        case .xboxSeries:
            return VirtualGamepadSpecification(
                identity: identity,
                descriptor: xboxSeriesDescriptor,
                vendorID: 0x045E,
                productID: 0x0B13,
                productName: "Xbox Wireless Controller",
                manufacturer: "Microsoft",
                versionNumber: 0x050F,
                ioKitTransport: "Bluetooth",
                serialNumber: "WMM-XBOX-P\(player)"
            )
        case .switchProSimple:
            return VirtualGamepadSpecification(
                identity: identity,
                descriptor: switchProDescriptor,
                vendorID: 0x057E,
                productID: 0x2009,
                productName: "Pro Controller",
                manufacturer: "Nintendo",
                versionNumber: 0x0001,
                ioKitTransport: "Bluetooth",
                serialNumber: "WMM-SWITCH-P\(player)"
            )
        }
    }

    static func reports(
        for state: VirtualGamepadState,
        identity: VirtualGamepadIdentity,
        previousState: VirtualGamepadState?
    ) -> [Data] {
        switch identity {
        case .generic:
            return [Data(genericReport(state))]
        case .xboxSeries:
            var reports = [Data(xboxNativeReport(state)), Data(xboxGIPReport(state))]
            let wasHomePressed = previousState?.has(.home) ?? false
            let isHomePressed = state.has(.home)
            if wasHomePressed != isHomePressed {
                reports.append(Data([0x07, 0x20, 0x00, 0x02, isHomePressed ? 0x01 : 0x00, 0x5B]))
            }
            return reports
        case .switchProSimple:
            return [Data(switchProSimpleReport(state))]
        }
    }

    static func primaryReport(
        for state: VirtualGamepadState,
        identity: VirtualGamepadIdentity
    ) -> Data {
        switch identity {
        case .generic: return Data(genericReport(state))
        case .xboxSeries: return Data(xboxNativeReport(state))
        case .switchProSimple: return Data(switchProSimpleReport(state))
        }
    }

    static func genericReport(_ state: VirtualGamepadState) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 8)
        report[0] = UInt8(bitPattern: state.leftX)
        report[1] = UInt8(bitPattern: state.leftY)
        report[2] = UInt8(bitPattern: state.rightX)
        report[3] = UInt8(bitPattern: state.rightY)
        report[4] = (state.hat & 0x0F) | (UInt8(state.buttons & 0x000F) << 4)
        report[5] = UInt8((state.buttons >> 4) & 0x00FF)
        report[6] = UInt8((state.buttons >> 12) & 0x000F)
        return report
    }

    static func xboxNativeReport(_ state: VirtualGamepadState) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 17)
        report[0] = 0x01

        // Apple's Xbox mapping for this descriptor treats a high Y value as up.
        writeLittleEndian(axis16(state.leftX), to: &report, at: 1)
        writeLittleEndian(axis16(negating: state.leftY), to: &report, at: 3)
        writeLittleEndian(axis16(state.rightX), to: &report, at: 5)
        writeLittleEndian(axis16(negating: state.rightY), to: &report, at: 7)

        writeLittleEndian(state.has(.leftTrigger) ? 1023 : 0, to: &report, at: 9)
        writeLittleEndian(state.has(.rightTrigger) ? 1023 : 0, to: &report, at: 11)
        report[13] = state.hat < 8 ? state.hat + 1 : 0

        if state.has(.south) { report[14] |= 0x01 }
        if state.has(.east) { report[14] |= 0x02 }
        if state.has(.west) { report[14] |= 0x08 }
        if state.has(.north) { report[14] |= 0x10 }
        if state.has(.leftShoulder) { report[14] |= 0x40 }
        if state.has(.rightShoulder) { report[14] |= 0x80 }

        if state.has(.select) { report[15] |= 0x04 }
        if state.has(.start) { report[15] |= 0x08 }
        if state.has(.home) { report[15] |= 0x10 }
        if state.has(.leftStick) { report[15] |= 0x20 }
        if state.has(.rightStick) { report[15] |= 0x40 }
        if state.has(.auxiliary1) { report[16] |= 0x01 }

        // SDL's GIP parser interprets byte 1 as flags. Prevent its fragment path
        // while preserving the byte offsets used by Apple's Xbox mapping.
        report[1] &= 0x7F
        return report
    }

    static func xboxGIPReport(_ state: VirtualGamepadState) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 19)
        report[0] = 0x20
        report[3] = 0x0F

        if state.has(.start) { report[4] |= 0x04 }
        if state.has(.select) { report[4] |= 0x08 }
        if state.has(.south) { report[4] |= 0x10 }
        if state.has(.east) { report[4] |= 0x20 }
        if state.has(.west) { report[4] |= 0x40 }
        if state.has(.north) { report[4] |= 0x80 }

        let directions = dpadDirections(fromHat: state.hat)
        if directions.up { report[5] |= 0x01 }
        if directions.down { report[5] |= 0x02 }
        if directions.left { report[5] |= 0x04 }
        if directions.right { report[5] |= 0x08 }
        if state.has(.leftShoulder) { report[5] |= 0x10 }
        if state.has(.rightShoulder) { report[5] |= 0x20 }
        if state.has(.leftStick) { report[5] |= 0x40 }
        if state.has(.rightStick) { report[5] |= 0x80 }

        writeLittleEndian(state.has(.leftTrigger) ? 1023 : 0, to: &report, at: 6)
        writeLittleEndian(state.has(.rightTrigger) ? 1023 : 0, to: &report, at: 8)
        writeLittleEndian(signedAxis16(state.leftX), to: &report, at: 10)
        writeLittleEndian(signedAxis16(negating: state.leftY), to: &report, at: 12)
        writeLittleEndian(signedAxis16(state.rightX), to: &report, at: 14)
        writeLittleEndian(signedAxis16(negating: state.rightY), to: &report, at: 16)
        if state.has(.auxiliary1) { report[18] |= 0x01 }
        return report
    }

    static func switchProSimpleReport(_ state: VirtualGamepadState) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 12)
        report[0] = 0x3F
        var buttons: UInt16 = 0
        if state.has(.south) { buttons |= 1 << 0 }       // B
        if state.has(.east) { buttons |= 1 << 1 }        // A
        if state.has(.west) { buttons |= 1 << 2 }        // Y
        if state.has(.north) { buttons |= 1 << 3 }       // X
        if state.has(.leftShoulder) { buttons |= 1 << 4 }
        if state.has(.rightShoulder) { buttons |= 1 << 5 }
        if state.has(.leftTrigger) { buttons |= 1 << 6 }
        if state.has(.rightTrigger) { buttons |= 1 << 7 }
        if state.has(.select) { buttons |= 1 << 8 }
        if state.has(.start) { buttons |= 1 << 9 }
        if state.has(.leftStick) { buttons |= 1 << 10 }
        if state.has(.rightStick) { buttons |= 1 << 11 }
        if state.has(.home) { buttons |= 1 << 12 }
        if state.has(.auxiliary1) { buttons |= 1 << 13 }
        report[1] = UInt8(buttons & 0xFF)
        report[2] = UInt8(buttons >> 8)
        report[3] = state.hat & 0x0F
        writeLittleEndian(axis16(state.leftX), to: &report, at: 4)
        writeLittleEndian(axis16(state.leftY), to: &report, at: 6)
        writeLittleEndian(axis16(state.rightX), to: &report, at: 8)
        writeLittleEndian(axis16(state.rightY), to: &report, at: 10)
        return report
    }

    private static func axis16(_ value: Int8) -> UInt16 {
        UInt16(clamping: 0x8000 + Int(value) * 258)
    }

    private static func axis16(negating value: Int8) -> UInt16 {
        axis16(Int8(clamping: -Int(value)))
    }

    private static func signedFullAxis(_ value: Int8) -> UInt16 {
        UInt16(bitPattern: Int16(clamping: Int(value) * 258))
    }

    private static func signedFullAxis(negating value: Int8) -> UInt16 {
        signedFullAxis(Int8(clamping: -Int(value)))
    }

    private static func signedAxis16(_ value: Int8) -> UInt16 {
        UInt16(bitPattern: Int16(clamping: Int(value) << 8))
    }

    private static func signedAxis16(negating value: Int8) -> UInt16 {
        signedAxis16(Int8(clamping: -Int(value)))
    }

    private static func writeLittleEndian(
        _ value: UInt16,
        to report: inout [UInt8],
        at index: Int
    ) {
        report[index] = UInt8(value & 0xFF)
        report[index + 1] = UInt8(value >> 8)
    }

    private static func dpadDirections(
        fromHat hat: UInt8
    ) -> (up: Bool, down: Bool, left: Bool, right: Bool) {
        switch hat {
        case 0: return (true, false, false, false)
        case 1: return (true, false, false, true)
        case 2: return (false, false, false, true)
        case 3: return (false, true, false, true)
        case 4: return (false, true, false, false)
        case 5: return (false, true, true, false)
        case 6: return (false, false, true, false)
        case 7: return (true, false, true, false)
        default: return (false, false, false, false)
        }
    }

    static let genericDescriptor: [UInt8] = [
        0x05,0x01,0x09,0x05,0xA1,0x01,
        0x09,0x01,0xA1,0x00,
        0x09,0x30,0x09,0x31,0x09,0x32,0x09,0x35,
        0x15,0x81,0x25,0x7F,0x75,0x08,0x95,0x04,0x81,0x02,
        0xC0,
        0x09,0x39,0x15,0x00,0x25,0x07,0x35,0x00,
        0x46,0x3B,0x01,0x65,0x14,0x75,0x04,0x95,0x01,0x81,0x42,
        0x05,0x09,0x19,0x01,0x29,0x10,0x15,0x00,0x25,0x01,
        0x75,0x01,0x95,0x10,0x81,0x02,
        0x75,0x01,0x95,0x0C,0x81,0x03,
        0xC0
    ]

    static let xboxSeriesDescriptor: [UInt8] = [
        0x05,0x01,0x09,0x05,0xA1,0x01,
        0x85,0x01,
        0x09,0x01,0xA1,0x00,
        0x09,0x30,0x09,0x31,
        0x15,0x00,0x27,0xFF,0xFF,0x00,0x00,
        0x95,0x02,0x75,0x10,0x81,0x02,0xC0,
        0x09,0x01,0xA1,0x00,
        0x09,0x32,0x09,0x35,
        0x15,0x00,0x27,0xFF,0xFF,0x00,0x00,
        0x95,0x02,0x75,0x10,0x81,0x02,0xC0,
        0x05,0x02,0x09,0xC5,
        0x15,0x00,0x26,0xFF,0x03,0x95,0x01,0x75,0x0A,0x81,0x02,
        0x15,0x00,0x25,0x00,0x75,0x06,0x95,0x01,0x81,0x03,
        0x05,0x02,0x09,0xC4,
        0x15,0x00,0x26,0xFF,0x03,0x95,0x01,0x75,0x0A,0x81,0x02,
        0x15,0x00,0x25,0x00,0x75,0x06,0x95,0x01,0x81,0x03,
        0x05,0x01,0x09,0x39,
        0x15,0x01,0x25,0x08,0x35,0x00,0x46,0x3B,0x01,
        0x66,0x14,0x00,0x75,0x04,0x95,0x01,0x81,0x42,
        0x75,0x04,0x95,0x01,0x15,0x00,0x25,0x00,
        0x35,0x00,0x45,0x00,0x65,0x00,0x81,0x03,
        0x05,0x09,0x19,0x01,0x29,0x0F,
        0x15,0x00,0x25,0x01,0x75,0x01,0x95,0x0F,0x81,0x02,
        0x15,0x00,0x25,0x00,0x75,0x01,0x95,0x01,0x81,0x03,
        0x05,0x0C,0x0A,0xB2,0x00,
        0x15,0x00,0x25,0x01,0x95,0x01,0x75,0x01,0x81,0x02,
        0x15,0x00,0x25,0x00,0x75,0x07,0x95,0x01,0x81,0x03,
        0x05,0x0F,0x09,0x21,0x85,0x03,0xA1,0x02,
        0x09,0x97,0x15,0x00,0x25,0x01,0x75,0x04,0x95,0x01,0x91,0x02,
        0x15,0x00,0x25,0x00,0x75,0x04,0x95,0x01,0x91,0x03,
        0x09,0x70,0x15,0x00,0x25,0x64,0x75,0x08,0x95,0x04,0x91,0x02,
        0x09,0x50,0x66,0x01,0x10,0x55,0x0E,
        0x15,0x00,0x26,0xFF,0x00,0x75,0x08,0x95,0x01,0x91,0x02,
        0x09,0xA7,0x15,0x00,0x26,0xFF,0x00,
        0x75,0x08,0x95,0x01,0x91,0x02,
        0x65,0x00,0x55,0x00,
        0x09,0x7C,0x15,0x00,0x26,0xFF,0x00,
        0x75,0x08,0x95,0x01,0x91,0x02,
        0xC0,
        0x06,0x00,0xFF,
        0x15,0x00,0x26,0xFF,0x00,
        0x75,0x08,
        0x85,0x07,0x09,0x07,0x95,0x05,0x81,0x02,
        0x85,0x20,0x09,0x20,0x95,0x12,0x81,0x02,
        0xC0
    ]

    static let switchProDescriptor: [UInt8] = [
        0x05,0x01,0x09,0x05,0xA1,0x01,
        0x06,0x01,0xFF,
        0x85,0x21,0x09,0x21,0x75,0x08,0x95,0x30,0x81,0x02,
        0x85,0x30,0x09,0x30,0x75,0x08,0x95,0x30,0x81,0x02,
        0x85,0x31,0x09,0x31,0x75,0x08,0x96,0x69,0x01,0x81,0x02,
        0x85,0x32,0x09,0x32,0x75,0x08,0x96,0x69,0x01,0x81,0x02,
        0x85,0x33,0x09,0x33,0x75,0x08,0x96,0x69,0x01,0x81,0x02,
        0x85,0x3F,
        0x05,0x09,0x19,0x01,0x29,0x10,
        0x15,0x00,0x25,0x01,0x75,0x01,0x95,0x10,0x81,0x02,
        0x05,0x01,0x09,0x39,0x15,0x00,0x25,0x07,
        0x75,0x04,0x95,0x01,0x81,0x42,
        0x05,0x09,0x75,0x04,0x95,0x01,0x81,0x01,
        0x05,0x01,0x09,0x30,0x09,0x31,0x09,0x33,0x09,0x34,
        0x16,0x00,0x00,0x27,0xFF,0xFF,0x00,0x00,
        0x75,0x10,0x95,0x04,0x81,0x02,
        0x06,0x01,0xFF,
        0x85,0x81,0x09,0x81,0x75,0x08,0x95,0x3F,0x81,0x02,
        0x85,0x01,0x09,0x01,0x75,0x08,0x95,0x30,0x91,0x02,
        0x85,0x10,0x09,0x10,0x75,0x08,0x95,0x30,0x91,0x02,
        0x85,0x11,0x09,0x11,0x75,0x08,0x95,0x30,0x91,0x02,
        0x85,0x12,0x09,0x12,0x75,0x08,0x95,0x30,0x91,0x02,
        0x85,0x80,0x09,0x80,0x75,0x08,0x95,0x3F,0x91,0x02,
        0xC0
    ]
}

private extension VirtualGamepadState {
    func has(_ button: VirtualGamepadButton) -> Bool {
        buttons & button.mask != 0
    }
}
