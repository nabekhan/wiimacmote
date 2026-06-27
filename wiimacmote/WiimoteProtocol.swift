import Foundation

enum WiimoteProtocolCodes {
    enum OutputReport {
        static let rumble: UInt8 = 0x10
        static let leds: UInt8 = 0x11
        static let reportMode: UInt8 = 0x12
        static let irEnable: UInt8 = 0x13
        static let speakerEnable: UInt8 = 0x14
        static let statusRequest: UInt8 = 0x15
        static let writeMemory: UInt8 = 0x16
        static let readMemory: UInt8 = 0x17
        static let speakerData: UInt8 = 0x18
        static let speakerMute: UInt8 = 0x19
        static let irEnable2: UInt8 = 0x1A
    }

    enum InputReport {
        static let status: UInt8 = 0x20
        static let readMemoryData: UInt8 = 0x21
        static let acknowledgment: UInt8 = 0x22
        static let buttons: UInt8 = 0x30
        static let buttonsAccelerometer: UInt8 = 0x31
        static let buttonsExtension8: UInt8 = 0x32
        static let buttonsAccelerometerIR12: UInt8 = 0x33
        static let buttonsExtension19: UInt8 = 0x34
        static let buttonsAccelerometerExtension16: UInt8 = 0x35
        static let buttonsIR10Extension9: UInt8 = 0x36
        static let buttonsAccelerometerIR10Extension6: UInt8 = 0x37
        static let extension21: UInt8 = 0x3D
        static let interleavedIR1: UInt8 = 0x3E
        static let interleavedIR2: UInt8 = 0x3F
    }

    enum OutputFlag {
        static let rumble: UInt8 = 0x01
        static let acknowledge: UInt8 = 0x02
        static let enable: UInt8 = 0x04
        static let continuous: UInt8 = 0x04
        static let registerAddressSpace: UInt8 = 0x04
    }

    enum Register {
        static let speakerConfiguration: UInt32 = 0xA2_00_01
        static let speakerFormat: UInt32 = 0xA2_00_09
        static let speakerEnable: UInt32 = 0xA2_00_08
        static let extensionInit: UInt32 = 0xA4_00_F0
        static let extensionDisableEncryption: UInt32 = 0xA4_00_FB
        static let extensionIdentifier: UInt32 = 0xA4_00_FA
        static let extensionData: UInt32 = 0xA4_00_08
        static let extensionCalibration: UInt32 = 0xA4_00_20
        static let motionPlusInit: UInt32 = 0xA6_00_F0
        static let motionPlusActivate: UInt32 = 0xA6_00_FE
        static let motionPlusIdentifier: UInt32 = 0xA6_00_FA
        static let motionPlusCalibration: UInt32 = 0xA6_00_20
        static let irModeControl: UInt32 = 0xB0_00_30
        static let irSensitivityBlock1: UInt32 = 0xB0_00_00
        static let irSensitivityBlock2: UInt32 = 0xB0_00_1A
        static let irMode: UInt32 = 0xB0_00_33
    }

    enum EEPROM {
        static let accelerometerCalibration: UInt32 = 0x00_00_16
    }

    static let outputReportNames: [UInt8: String] = [
        OutputReport.rumble: "Rumble",
        OutputReport.leds: "Player LEDs",
        OutputReport.reportMode: "Data Reporting Mode",
        OutputReport.irEnable: "IR Camera Enable",
        OutputReport.speakerEnable: "Speaker Enable",
        OutputReport.statusRequest: "Status Request",
        OutputReport.writeMemory: "Write Memory/Register",
        OutputReport.readMemory: "Read Memory/Register",
        OutputReport.speakerData: "Speaker Data",
        OutputReport.speakerMute: "Speaker Mute",
        OutputReport.irEnable2: "IR Camera Enable 2"
    ]

    static let inputReportNames: [UInt8: String] = [
        InputReport.status: "Status",
        InputReport.readMemoryData: "Read Memory Data",
        InputReport.acknowledgment: "Acknowledgement",
        InputReport.buttons: "Core Buttons",
        InputReport.buttonsAccelerometer: "Core Buttons + Accelerometer",
        InputReport.buttonsExtension8: "Core Buttons + 8 Extension Bytes",
        InputReport.buttonsAccelerometerIR12: "Core Buttons + Accelerometer + 12 IR Bytes",
        InputReport.buttonsExtension19: "Core Buttons + 19 Extension Bytes",
        InputReport.buttonsAccelerometerExtension16: "Core Buttons + Accelerometer + 16 Extension Bytes",
        InputReport.buttonsIR10Extension9: "Core Buttons + 10 IR Bytes + 9 Extension Bytes",
        InputReport.buttonsAccelerometerIR10Extension6: "Core Buttons + Accelerometer + 10 IR Bytes + 6 Extension Bytes",
        InputReport.extension21: "21 Extension Bytes",
        InputReport.interleavedIR1: "Interleaved IR 1",
        InputReport.interleavedIR2: "Interleaved IR 2"
    ]
}

/// Button bits used by Nintendo's Wii Remote input reports.
///
/// The two core bytes are little-endian on current macOS hosts. Bits 5 and 6
/// in each byte can carry accelerometer precision data in motion report modes,
/// so callers should use `buttonMask` before treating the value as buttons.
struct WiimoteButtons: OptionSet, Hashable, Sendable {
    let rawValue: UInt16

    static let dpadLeft  = WiimoteButtons(rawValue: 0x0001)
    static let dpadRight = WiimoteButtons(rawValue: 0x0002)
    static let dpadDown  = WiimoteButtons(rawValue: 0x0004)
    static let dpadUp    = WiimoteButtons(rawValue: 0x0008)
    static let plus      = WiimoteButtons(rawValue: 0x0010)

    static let two       = WiimoteButtons(rawValue: 0x0100)
    static let one       = WiimoteButtons(rawValue: 0x0200)
    static let b         = WiimoteButtons(rawValue: 0x0400)
    static let a         = WiimoteButtons(rawValue: 0x0800)
    static let minus     = WiimoteButtons(rawValue: 0x1000)
    static let home      = WiimoteButtons(rawValue: 0x8000)

    static let buttonMask: UInt16 = 0x9F1F

    var labels: [String] {
        var result: [String] = []
        let ordered: [(WiimoteButtons, String)] = [
            (.dpadUp, "↑"), (.dpadDown, "↓"), (.dpadLeft, "←"), (.dpadRight, "→"),
            (.a, "A"), (.b, "B"), (.one, "1"), (.two, "2"),
            (.plus, "+"), (.minus, "−"), (.home, "Home")
        ]
        for (button, label) in ordered where contains(button) {
            result.append(label)
        }
        return result
    }
}

struct WiimoteAcceleration: Equatable, Sendable {
    let rawX: UInt16
    let rawY: UInt16
    let rawZ: UInt16

    /// Approximate acceleration in g using the common uncalibrated Wii Remote
    /// center (~512) and one-g span (~128). Per-device EEPROM calibration is a
    /// future enhancement; this approximation is sufficient for tilt mapping.
    var xG: Double { (Double(rawX) - 512.0) / 128.0 }
    var yG: Double { (Double(rawY) - 512.0) / 128.0 }
    var zG: Double { (Double(rawZ) - 512.0) / 128.0 }
}

struct WiimoteInput: Equatable, Sendable {
    let reportID: UInt8
    let buttons: WiimoteButtons
    let acceleration: WiimoteAcceleration?
    let irData: [UInt8]
    let extensionData: [UInt8]

    var irPoints: [WiimoteIRPoint] {
        WiimoteIRPoint.parse(irData)
    }
}

struct WiimoteStatus: Equatable, Sendable {
    let buttons: WiimoteButtons
    let batteryRaw: UInt8
    let batteryPercent: Int
    let extensionConnected: Bool
    let speakerEnabled: Bool
    let infraredEnabled: Bool
    let ledMask: UInt8
}

struct WiimoteReadData: Equatable, Sendable {
    let buttons: WiimoteButtons
    let size: Int
    let error: UInt8
    let offsetLow: UInt16
    let data: [UInt8]
}

struct WiimoteOutputReport: Equatable, Sendable {
    let reportID: UInt8
    let payload: [UInt8]
}

enum WiimoteAddressSpace: Equatable, Sendable {
    case eeprom
    case register
}

enum WiimoteReportMode: UInt8, Sendable {
    case buttons = 0x30
    case buttonsAccelerometer = 0x31
    case buttonsExtension8 = 0x32
    case buttonsAccelerometerIR12 = 0x33
    case buttonsExtension19 = 0x34
    case buttonsAccelerometerExtension16 = 0x35
    case buttonsIR10Extension9 = 0x36
    case buttonsAccelerometerIR10Extension6 = 0x37
    case extension21 = 0x3D
    case interleavedIR1 = 0x3E
    case interleavedIR2 = 0x3F
}

enum WiimoteMotionPlusMode: UInt8, Sendable {
    case standalone = 0x04
    case nunchukPassthrough = 0x05
    case classicPassthrough = 0x07

    var displayName: String {
        switch self {
        case .standalone: return "standalone"
        case .nunchukPassthrough: return "Nunchuk passthrough"
        case .classicPassthrough: return "Classic passthrough"
        }
    }
}

enum WiimoteRemoteKind: String, Codable, Sendable {
    case standard
    case motionPlusInside
    case balanceBoard
    case unknown

    init(name: String?, productID: Int?) {
        let normalizedName = (name ?? "").uppercased()
        if normalizedName.contains("RVL-WBC") {
            self = .balanceBoard
        } else if productID == 0x0330 || normalizedName.contains("RVL-CNT-01-TR") {
            self = .motionPlusInside
        } else if productID == 0x0306 || normalizedName.contains("RVL-CNT-01") || normalizedName.contains("WIIMOTE") {
            self = .standard
        } else {
            self = .unknown
        }
    }

    var title: String {
        switch self {
        case .standard: return "Wii Remote"
        case .motionPlusInside: return "Wii Remote Plus"
        case .balanceBoard: return "Wii Fit Balance Board"
        case .unknown: return "Unknown Wii Controller"
        }
    }
}

enum WiimoteMotionPlusCapability: String, Codable, Sendable {
    case unknown
    case absent
    case accessoryPresent
    case insidePresent
    case activeStandalone
    case activeNunchukPassthrough
    case activeClassicPassthrough

    init(remoteKind: WiimoteRemoteKind) {
        self = remoteKind == .motionPlusInside ? .insidePresent : .unknown
    }

    init?(identifier: [UInt8], remoteKind: WiimoteRemoteKind) {
        switch identifier {
        case [0x00, 0x00, 0xA4, 0x20, 0x00, 0x05]: self = .insidePresent
        case [0x00, 0x00, 0xA6, 0x20, 0x00, 0x05],
             [0x01, 0x00, 0xA6, 0x20, 0x00, 0x05]: self = .accessoryPresent
        case [0x00, 0x00, 0xA4, 0x20, 0x04, 0x05],
             [0x00, 0x00, 0xA6, 0x20, 0x04, 0x05],
             [0x01, 0x00, 0xA6, 0x20, 0x04, 0x05]: self = .activeStandalone
        case [0x00, 0x00, 0xA4, 0x20, 0x05, 0x05],
             [0x00, 0x00, 0xA6, 0x20, 0x05, 0x05],
             [0x01, 0x00, 0xA6, 0x20, 0x05, 0x05]: self = .activeNunchukPassthrough
        case [0x00, 0x00, 0xA4, 0x20, 0x07, 0x05],
             [0x00, 0x00, 0xA6, 0x20, 0x07, 0x05],
             [0x01, 0x00, 0xA6, 0x20, 0x07, 0x05]: self = .activeClassicPassthrough
        default:
            if remoteKind == .motionPlusInside {
                self = .insidePresent
            } else {
                return nil
            }
        }
    }

    var title: String {
        switch self {
        case .unknown: return "MotionPlus unknown"
        case .absent: return "No MotionPlus"
        case .accessoryPresent: return "MotionPlus accessory detected"
        case .insidePresent: return "MotionPlus inside"
        case .activeStandalone: return "MotionPlus active"
        case .activeNunchukPassthrough: return "MotionPlus + Nunchuk active"
        case .activeClassicPassthrough: return "MotionPlus + Classic active"
        }
    }

    var isKnownPresent: Bool {
        switch self {
        case .accessoryPresent, .insidePresent, .activeStandalone, .activeNunchukPassthrough, .activeClassicPassthrough:
            return true
        case .unknown, .absent:
            return false
        }
    }
}

enum WiimoteIdentifierFormatter {
    static func hexString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

enum WiimoteOutputReports {
    static func rumble(enabled: Bool) -> WiimoteOutputReport {
        WiimoteOutputReport(
            reportID: WiimoteProtocolCodes.OutputReport.rumble,
            payload: [enabled ? WiimoteProtocolCodes.OutputFlag.rumble : 0x00]
        )
    }

    static func leds(mask: UInt8, rumble: Bool) -> WiimoteOutputReport {
        WiimoteOutputReport(
            reportID: WiimoteProtocolCodes.OutputReport.leds,
            payload: [(mask & 0xF0) | (rumble ? WiimoteProtocolCodes.OutputFlag.rumble : 0x00)]
        )
    }

    static func reportMode(
        _ mode: WiimoteReportMode,
        continuous: Bool = true,
        rumble: Bool = false
    ) -> WiimoteOutputReport {
        var flags: UInt8 = continuous ? WiimoteProtocolCodes.OutputFlag.continuous : 0x00
        if rumble { flags |= WiimoteProtocolCodes.OutputFlag.rumble }
        return WiimoteOutputReport(
            reportID: WiimoteProtocolCodes.OutputReport.reportMode,
            payload: [flags, mode.rawValue]
        )
    }

    static func irEnabled(_ enabled: Bool, second: Bool = false, rumble: Bool = false) -> WiimoteOutputReport {
        var flags: UInt8 = enabled ? WiimoteProtocolCodes.OutputFlag.enable : 0x00
        if rumble { flags |= WiimoteProtocolCodes.OutputFlag.rumble }
        return WiimoteOutputReport(
            reportID: second ? WiimoteProtocolCodes.OutputReport.irEnable2 : WiimoteProtocolCodes.OutputReport.irEnable,
            payload: [flags]
        )
    }

    static func speakerEnabled(_ enabled: Bool, rumble: Bool = false) -> WiimoteOutputReport {
        var flags: UInt8 = enabled ? WiimoteProtocolCodes.OutputFlag.enable : 0x00
        if rumble { flags |= WiimoteProtocolCodes.OutputFlag.rumble }
        return WiimoteOutputReport(reportID: WiimoteProtocolCodes.OutputReport.speakerEnable, payload: [flags])
    }

    static func statusRequest(rumble: Bool = false) -> WiimoteOutputReport {
        WiimoteOutputReport(
            reportID: WiimoteProtocolCodes.OutputReport.statusRequest,
            payload: [rumble ? WiimoteProtocolCodes.OutputFlag.rumble : 0x00]
        )
    }

    static func writeMemory(
        addressSpace: WiimoteAddressSpace,
        address: UInt32,
        bytes: [UInt8],
        rumble: Bool = false
    ) -> WiimoteOutputReport? {
        guard (1...16).contains(bytes.count), address <= 0xFF_FFFF else { return nil }
        var flags: UInt8 = addressSpace == .register ? WiimoteProtocolCodes.OutputFlag.registerAddressSpace : 0x00
        if rumble { flags |= WiimoteProtocolCodes.OutputFlag.rumble }

        var payload: [UInt8] = [
            flags,
            UInt8((address >> 16) & 0xFF),
            UInt8((address >> 8) & 0xFF),
            UInt8(address & 0xFF),
            UInt8(bytes.count)
        ]
        payload.append(contentsOf: bytes)
        payload.append(contentsOf: repeatElement(0, count: 16 - bytes.count))
        return WiimoteOutputReport(reportID: WiimoteProtocolCodes.OutputReport.writeMemory, payload: payload)
    }

    static func readMemory(
        addressSpace: WiimoteAddressSpace,
        address: UInt32,
        length: UInt16,
        rumble: Bool = false
    ) -> WiimoteOutputReport? {
        guard length > 0, address <= 0xFF_FFFF else { return nil }
        var flags: UInt8 = addressSpace == .register ? WiimoteProtocolCodes.OutputFlag.registerAddressSpace : 0x00
        if rumble { flags |= WiimoteProtocolCodes.OutputFlag.rumble }
        return WiimoteOutputReport(
            reportID: WiimoteProtocolCodes.OutputReport.readMemory,
            payload: [
                flags,
                UInt8((address >> 16) & 0xFF),
                UInt8((address >> 8) & 0xFF),
                UInt8(address & 0xFF),
                UInt8((length >> 8) & 0xFF),
                UInt8(length & 0xFF)
            ]
        )
    }

    static func speakerData(_ data: [UInt8], rumble: Bool = false) -> WiimoteOutputReport? {
        guard data.count <= 20 else { return nil }
        var flags = UInt8(data.count << 3)
        if rumble { flags |= WiimoteProtocolCodes.OutputFlag.rumble }
        var payload = [flags]
        payload.append(contentsOf: data)
        payload.append(contentsOf: repeatElement(0, count: 20 - data.count))
        return WiimoteOutputReport(reportID: WiimoteProtocolCodes.OutputReport.speakerData, payload: payload)
    }

    static func speakerMuted(_ muted: Bool, rumble: Bool = false) -> WiimoteOutputReport {
        var flags: UInt8 = muted ? WiimoteProtocolCodes.OutputFlag.enable : 0x00
        if rumble { flags |= WiimoteProtocolCodes.OutputFlag.rumble }
        return WiimoteOutputReport(reportID: WiimoteProtocolCodes.OutputReport.speakerMute, payload: [flags])
    }

    static func extensionInitializationSequence() -> [WiimoteOutputReport] {
        [
            writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.extensionInit, bytes: [0x55]),
            writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.extensionDisableEncryption, bytes: [0x00])
        ].compactMap { $0 }
    }

    static func readExtensionIdentifier() -> WiimoteOutputReport? {
        readMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.extensionIdentifier, length: 6)
    }

    static func readMotionPlusIdentifier() -> WiimoteOutputReport? {
        readMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.motionPlusIdentifier, length: 6)
    }

    static func readAccelerometerCalibration() -> WiimoteOutputReport? {
        readMemory(addressSpace: .eeprom, address: WiimoteProtocolCodes.EEPROM.accelerometerCalibration, length: 10)
    }

    static func readBalanceBoardCalibration() -> WiimoteOutputReport? {
        readMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.extensionCalibration, length: 32)
    }

    static func speakerInitializationSequence() -> [WiimoteOutputReport] {
        [
            speakerEnabled(true),
            speakerMuted(true),
            writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.speakerFormat, bytes: [0x01]),
            writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.speakerConfiguration, bytes: [0x08]),
            writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.speakerConfiguration, bytes: [0x00, 0x00, 0xD0, 0x07, 0x40, 0x00, 0x00]),
            writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.speakerEnable, bytes: [0x01]),
            speakerMuted(false)
        ].compactMap { $0 }
    }

    static func motionPlusInitialize() -> WiimoteOutputReport? {
        writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.motionPlusInit, bytes: [0x55])
    }

    static func motionPlusActivate(mode: WiimoteMotionPlusMode) -> WiimoteOutputReport? {
        writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.motionPlusActivate, bytes: [mode.rawValue])
    }

    static func motionPlusDeactivate() -> WiimoteOutputReport? {
        writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.extensionInit, bytes: [0x55])
    }

    static func irInitializationSequence(mode: WiimoteIRMode = .extended) -> [WiimoteOutputReport] {
        [
            irEnabled(true),
            irEnabled(true, second: true),
            writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.irModeControl, bytes: [0x08]),
            writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.irSensitivityBlock1, bytes: WiimoteIRSensitivity.block1),
            writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.irSensitivityBlock2, bytes: WiimoteIRSensitivity.block2),
            writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.irMode, bytes: [mode.rawValue]),
            writeMemory(addressSpace: .register, address: WiimoteProtocolCodes.Register.irModeControl, bytes: [0x08])
        ].compactMap { $0 }
    }
}

enum WiimoteIRMode: UInt8, Sendable {
    case basic = 0x01
    case extended = 0x03
    case full = 0x05

    var displayName: String {
        switch self {
        case .basic: return "basic"
        case .extended: return "extended"
        case .full: return "full"
        }
    }
}

enum WiimoteIRSensitivity {
    static let block1: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x90, 0x00, 0x41]
    static let block2: [UInt8] = [0x40, 0x00]
}

struct WiimoteIRPoint: Equatable, Sendable {
    let x: UInt16
    let y: UInt16
    let size: UInt8?

    static func parse(_ data: [UInt8]) -> [WiimoteIRPoint] {
        switch data.count {
        case 10:
            return parseBasic(data)
        case 12:
            return stride(from: 0, to: 12, by: 3).compactMap { parseExtended(Array(data[$0..<($0 + 3)])) }
        case 18:
            return stride(from: 0, to: 18, by: 9).compactMap { parseFull(Array(data[$0..<($0 + 9)])) }
        case 36:
            return stride(from: 0, to: 36, by: 9).compactMap { parseFull(Array(data[$0..<($0 + 9)])) }
        default:
            return []
        }
    }

    private static func parseBasic(_ data: [UInt8]) -> [WiimoteIRPoint] {
        guard data.count >= 10 else { return [] }
        return [
            parseBasicPair(data, offset: 0).0,
            parseBasicPair(data, offset: 0).1,
            parseBasicPair(data, offset: 5).0,
            parseBasicPair(data, offset: 5).1
        ].compactMap { $0 }
    }

    private static func parseBasicPair(
        _ data: [UInt8],
        offset: Int
    ) -> (WiimoteIRPoint?, WiimoteIRPoint?) {
        let x1 = UInt16(data[offset]) | (UInt16((data[offset + 4] >> 4) & 0x03) << 8)
        let y1 = UInt16(data[offset + 1]) | (UInt16((data[offset + 4] >> 6) & 0x03) << 8)
        let x2 = UInt16(data[offset + 2]) | (UInt16(data[offset + 4] & 0x03) << 8)
        let y2 = UInt16(data[offset + 3]) | (UInt16((data[offset + 4] >> 2) & 0x03) << 8)
        return (
            pointIfVisible(x: x1, y: y1, size: nil),
            pointIfVisible(x: x2, y: y2, size: nil)
        )
    }

    private static func parseExtended(_ data: [UInt8]) -> WiimoteIRPoint? {
        guard data.count == 3 else { return nil }
        let x = UInt16(data[0]) | (UInt16((data[2] >> 4) & 0x03) << 8)
        let y = UInt16(data[1]) | (UInt16((data[2] >> 6) & 0x03) << 8)
        return pointIfVisible(x: x, y: y, size: data[2] & 0x0F)
    }

    private static func parseFull(_ data: [UInt8]) -> WiimoteIRPoint? {
        guard data.count == 9 else { return nil }
        return parseExtended(Array(data[0..<3]))
    }

    private static func pointIfVisible(x: UInt16, y: UInt16, size: UInt8?) -> WiimoteIRPoint? {
        guard x != 0x03FF || y != 0x03FF else { return nil }
        return WiimoteIRPoint(x: x, y: y, size: size)
    }
}

enum WiimotePacket: Equatable, Sendable {
    case input(WiimoteInput)
    case status(WiimoteStatus)
    case readData(WiimoteReadData)
    case acknowledgment(reportID: UInt8, error: UInt8)
    case ignored(reportID: UInt8)
}

enum WiimoteReportParser {
    /// Parses the raw report passed by IOHID. The first byte must be the Wii
    /// Remote report ID (for example, 0x30 or 0x31).
    static func parse(_ bytes: UnsafeBufferPointer<UInt8>) -> WiimotePacket? {
        guard let reportID = bytes.first else { return nil }

        switch reportID {
        case 0x20:
            return parseStatus(bytes)

        case 0x21:
            return parseReadData(bytes)

        case 0x22:
            guard bytes.count >= 5 else { return nil }
            return .acknowledgment(reportID: bytes[3], error: bytes[4])

        case 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x3D, 0x3E, 0x3F:
            return parseInput(bytes, reportID: reportID)

        default:
            return .ignored(reportID: reportID)
        }
    }

    static func parse(_ data: Data) -> WiimotePacket? {
        data.withUnsafeBytes { rawBuffer in
            let typed = rawBuffer.bindMemory(to: UInt8.self)
            return parse(typed)
        }
    }

    private static func parseStatus(_ bytes: UnsafeBufferPointer<UInt8>) -> WiimotePacket? {
        guard bytes.count >= 7 else { return nil }

        let buttons = parseButtons(bytes, firstButtonIndex: 1)
        let flags = bytes[3]
        let rawBattery = bytes[6]

        // The protocol exposes battery voltage as an unsigned 0...255 level.
        // Treat it as an estimate rather than a chemistry-aware capacity meter.
        let percent = Int((Double(rawBattery) / 255.0 * 100.0).rounded())
            .clamped(to: 0...100)

        return .status(
            WiimoteStatus(
                buttons: buttons,
                batteryRaw: rawBattery,
                batteryPercent: percent,
                extensionConnected: (flags & 0x02) != 0,
                speakerEnabled: (flags & 0x04) != 0,
                infraredEnabled: (flags & 0x08) != 0,
                ledMask: flags & 0xF0
            )
        )
    }

    private static func parseReadData(_ bytes: UnsafeBufferPointer<UInt8>) -> WiimotePacket? {
        guard bytes.count >= 22 else { return nil }
        let sizeAndError = bytes[3]
        let size = Int(sizeAndError >> 4) + 1
        guard (1...16).contains(size) else { return nil }
        let data = Array(bytes[6..<(6 + size)])

        return .readData(
            WiimoteReadData(
                buttons: parseButtons(bytes, firstButtonIndex: 1),
                size: size,
                error: sizeAndError & 0x0F,
                offsetLow: (UInt16(bytes[4]) << 8) | UInt16(bytes[5]),
                data: data
            )
        )
    }

    private static func parseInput(
        _ bytes: UnsafeBufferPointer<UInt8>,
        reportID: UInt8
    ) -> WiimotePacket? {
        if reportID == 0x3D {
            guard bytes.count >= 22 else { return nil }
            return .input(
                WiimoteInput(
                    reportID: reportID,
                    buttons: [],
                    acceleration: nil,
                    irData: [],
                    extensionData: Array(bytes[1..<22])
                )
            )
        }

        if reportID == 0x3E || reportID == 0x3F {
            guard bytes.count >= 22 else { return nil }
            return .input(
                WiimoteInput(
                    reportID: reportID,
                    buttons: parseButtons(bytes, firstButtonIndex: 1),
                    acceleration: nil,
                    irData: Array(bytes[4..<22]),
                    extensionData: []
                )
            )
        }

        guard bytes.count >= 3 else { return nil }
        let buttons = parseButtons(bytes, firstButtonIndex: 1)

        let acceleration: WiimoteAcceleration?
        switch reportID {
        case 0x31, 0x33, 0x35, 0x37:
            guard bytes.count >= 6 else { return nil }
            acceleration = parseAcceleration(bytes)
        default:
            acceleration = nil
        }

        let irRange: Range<Int>?
        switch reportID {
        case 0x33: irRange = 6..<18
        case 0x36: irRange = 3..<13
        case 0x37: irRange = 6..<16
        default: irRange = nil
        }

        let extensionRange: Range<Int>?
        switch reportID {
        case 0x32: extensionRange = 3..<11
        case 0x34: extensionRange = 3..<22
        case 0x35: extensionRange = 6..<22
        case 0x36: extensionRange = 13..<22
        case 0x37: extensionRange = 16..<22
        default: extensionRange = nil
        }

        let extensionData: [UInt8]
        if let extensionRange {
            guard bytes.count >= extensionRange.upperBound else { return nil }
            extensionData = Array(bytes[extensionRange])
        } else {
            extensionData = []
        }

        let irData: [UInt8]
        if let irRange {
            guard bytes.count >= irRange.upperBound else { return nil }
            irData = Array(bytes[irRange])
        } else {
            irData = []
        }

        return .input(
            WiimoteInput(
                reportID: reportID,
                buttons: buttons,
                acceleration: acceleration,
                irData: irData,
                extensionData: extensionData
            )
        )
    }

    private static func parseButtons(
        _ bytes: UnsafeBufferPointer<UInt8>,
        firstButtonIndex: Int
    ) -> WiimoteButtons {
        guard bytes.count > firstButtonIndex + 1 else { return [] }
        let raw = UInt16(bytes[firstButtonIndex]) |
            (UInt16(bytes[firstButtonIndex + 1]) << 8)
        return WiimoteButtons(rawValue: raw & WiimoteButtons.buttonMask)
    }

    private static func parseAcceleration(
        _ bytes: UnsafeBufferPointer<UInt8>
    ) -> WiimoteAcceleration {
        // X carries 10 bits. Y/Z expose 9 effective bits in the same 10-bit
        // coordinate space, so their unavailable least-significant bit is zero.
        let x = (UInt16(bytes[3]) << 2) | UInt16((bytes[1] >> 5) & 0x03)
        let y = (UInt16(bytes[4]) << 2) | UInt16((bytes[2] >> 4) & 0x02)
        let z = (UInt16(bytes[5]) << 2) | UInt16((bytes[2] >> 5) & 0x02)
        return WiimoteAcceleration(rawX: x, rawY: y, rawZ: z)
    }
}

struct WiimoteAccelerometerCalibration: Equatable, Sendable {
    let zero: WiimoteAcceleration
    let oneG: WiimoteAcceleration
    let checksumValid: Bool

    init?(bytes: [UInt8]) {
        guard bytes.count >= 10 else { return nil }
        self.zero = WiimoteAccelerometerCalibration.decodeAcceleration(
            xHigh: bytes[0],
            yHigh: bytes[1],
            zHigh: bytes[2],
            lowBits: bytes[3]
        )
        self.oneG = WiimoteAccelerometerCalibration.decodeAcceleration(
            xHigh: bytes[4],
            yHigh: bytes[5],
            zHigh: bytes[6],
            lowBits: bytes[7]
        )
        let checksum = bytes[0..<9].reduce(UInt8(0x55)) { partial, byte in
            partial &+ byte
        }
        self.checksumValid = checksum == bytes[9]
    }

    func calibratedG(for acceleration: WiimoteAcceleration) -> (x: Double, y: Double, z: Double) {
        (
            axisG(raw: acceleration.rawX, zero: zero.rawX, oneG: oneG.rawX),
            axisG(raw: acceleration.rawY, zero: zero.rawY, oneG: oneG.rawY),
            axisG(raw: acceleration.rawZ, zero: zero.rawZ, oneG: oneG.rawZ)
        )
    }

    private func axisG(raw: UInt16, zero: UInt16, oneG: UInt16) -> Double {
        let span = max(1.0, Double(oneG) - Double(zero))
        return (Double(raw) - Double(zero)) / span
    }

    private static func decodeAcceleration(
        xHigh: UInt8,
        yHigh: UInt8,
        zHigh: UInt8,
        lowBits: UInt8
    ) -> WiimoteAcceleration {
        WiimoteAcceleration(
            rawX: (UInt16(xHigh) << 2) | UInt16((lowBits >> 4) & 0x03),
            rawY: (UInt16(yHigh) << 2) | UInt16((lowBits >> 2) & 0x03),
            rawZ: (UInt16(zHigh) << 2) | UInt16(lowBits & 0x03)
        )
    }
}

enum WiimoteExtensionKind: Equatable, Sendable {
    case nunchuk
    case classicController
    case classicControllerPro
    case balanceBoard
    case motionPlusInactive
    case motionPlusActive
    case motionPlusNunchukPassthrough
    case motionPlusClassicPassthrough
    case guitar
    case drums
    case tatacon
    case unknown(identifier: [UInt8])

    init(identifier: [UInt8]) {
        switch identifier {
        case [0x00, 0x00, 0xA4, 0x20, 0x00, 0x00]: self = .nunchuk
        case [0x00, 0x00, 0xA4, 0x20, 0x01, 0x01]: self = .classicController
        case [0x01, 0x00, 0xA4, 0x20, 0x01, 0x01]: self = .classicControllerPro
        case [0x00, 0x00, 0xA4, 0x20, 0x04, 0x02]: self = .balanceBoard
        case [0x00, 0x00, 0xA4, 0x20, 0x00, 0x05],
             [0x00, 0x00, 0xA6, 0x20, 0x00, 0x05],
             [0x01, 0x00, 0xA6, 0x20, 0x00, 0x05]: self = .motionPlusInactive
        case [0x00, 0x00, 0xA4, 0x20, 0x04, 0x05],
             [0x00, 0x00, 0xA6, 0x20, 0x04, 0x05],
             [0x01, 0x00, 0xA6, 0x20, 0x04, 0x05]: self = .motionPlusActive
        case [0x00, 0x00, 0xA4, 0x20, 0x05, 0x05],
             [0x00, 0x00, 0xA6, 0x20, 0x05, 0x05],
             [0x01, 0x00, 0xA6, 0x20, 0x05, 0x05]: self = .motionPlusNunchukPassthrough
        case [0x00, 0x00, 0xA4, 0x20, 0x07, 0x05],
             [0x00, 0x00, 0xA6, 0x20, 0x07, 0x05],
             [0x01, 0x00, 0xA6, 0x20, 0x07, 0x05]: self = .motionPlusClassicPassthrough
        case [0x00, 0x00, 0xA4, 0x20, 0x01, 0x03]: self = .guitar
        case [0x01, 0x00, 0xA4, 0x20, 0x01, 0x03]: self = .drums
        case [0x00, 0x00, 0xA4, 0x20, 0x01, 0x11]: self = .tatacon
        default: self = .unknown(identifier: identifier)
        }
    }

    static func identifierLooksInvalid(_ identifier: [UInt8]) -> Bool {
        guard identifier.count >= 6 else { return true }
        return identifier.prefix(6).allSatisfy { $0 == 0x00 } ||
            identifier.prefix(6).allSatisfy { $0 == 0xFF }
    }

    var displayName: String {
        switch self {
        case .nunchuk: return "Nunchuk"
        case .classicController: return "Classic Controller"
        case .classicControllerPro: return "Classic Controller Pro"
        case .balanceBoard: return "Wii Fit Balance Board"
        case .motionPlusInactive: return "MotionPlus inactive"
        case .motionPlusActive: return "MotionPlus"
        case .motionPlusNunchukPassthrough: return "MotionPlus + Nunchuk"
        case .motionPlusClassicPassthrough: return "MotionPlus + Classic"
        case .guitar: return "Guitar Controller"
        case .drums: return "Drums Controller"
        case .tatacon: return "TaTaCon Drum"
        case .unknown: return "Unknown Extension"
        }
    }

    var isMotionPlus: Bool {
        switch self {
        case .motionPlusInactive, .motionPlusActive, .motionPlusNunchukPassthrough, .motionPlusClassicPassthrough:
            return true
        default:
            return false
        }
    }

    var isMotionPlusInactive: Bool {
        self == .motionPlusInactive
    }

    var isMotionPlusActive: Bool {
        switch self {
        case .motionPlusActive, .motionPlusNunchukPassthrough, .motionPlusClassicPassthrough:
            return true
        default:
            return false
        }
    }

    var isMotionPlusPassthrough: Bool {
        switch self {
        case .motionPlusNunchukPassthrough, .motionPlusClassicPassthrough:
            return true
        default:
            return false
        }
    }
}

enum WiimoteExtensionInput: Equatable, Sendable {
    case nunchuk(WiimoteNunchukInput)
    case classicController(WiimoteClassicControllerInput)
    case guitar(WiimoteGuitarInput)
    case motionPlus(WiimoteMotionPlusInput)
    case balanceBoard(WiimoteBalanceBoardInput)
    case tatacon(WiimoteTataconInput)
    case raw(kind: WiimoteExtensionKind, bytes: [UInt8])

    static func decode(_ bytes: [UInt8], kind: WiimoteExtensionKind?) -> WiimoteExtensionInput? {
        guard !bytes.isEmpty else { return nil }
        switch kind {
        case .nunchuk:
            return WiimoteNunchukInput(bytes: bytes).map { .nunchuk($0) }
        case .classicController, .classicControllerPro:
            return WiimoteClassicControllerInput(bytes: bytes).map { .classicController($0) }
        case .guitar:
            return WiimoteGuitarInput(bytes: bytes).map { .guitar($0) }
        case .motionPlusActive, .motionPlusInactive:
            return WiimoteMotionPlusInput(bytes: bytes).map { .motionPlus($0) }
        case .motionPlusNunchukPassthrough:
            if WiimoteMotionPlusInput.isMotionPlusPacket(bytes) {
                return WiimoteMotionPlusInput(bytes: bytes).map { .motionPlus($0) }
            }
            return WiimoteNunchukInput(passthroughBytes: bytes).map { .nunchuk($0) }
        case .motionPlusClassicPassthrough:
            if WiimoteMotionPlusInput.isMotionPlusPacket(bytes) {
                return WiimoteMotionPlusInput(bytes: bytes).map { .motionPlus($0) }
            }
            return WiimoteClassicControllerInput(passthroughBytes: bytes).map { .classicController($0) }
        case .balanceBoard:
            return WiimoteBalanceBoardInput(bytes: bytes).map { .balanceBoard($0) }
        case .tatacon:
            return WiimoteTataconInput(bytes: bytes).map { .tatacon($0) }
        case .drums, .unknown:
            return .raw(kind: kind ?? .unknown(identifier: []), bytes: bytes)
        case .none:
            return .raw(kind: .unknown(identifier: []), bytes: bytes)
        }
    }

    var summary: String {
        switch self {
        case .nunchuk(let input):
            let buttons = [input.cPressed ? "C" : nil, input.zPressed ? "Z" : nil]
                .compactMap { $0 }
                .joined(separator: "+")
            return "Stick \(input.stickX),\(input.stickY)" + (buttons.isEmpty ? "" : " · \(buttons)")
        case .classicController(let input):
            return "LX \(input.leftX) LY \(input.leftY) · \(input.buttons.labels.joined(separator: "+"))"
        case .guitar(let input):
            return "Stick \(input.stickX),\(input.stickY) · \(input.buttons.labels.joined(separator: "+")) · whammy \(input.whammyPercent)%"
        case .motionPlus(let input):
            return "Yaw \(input.yaw) Roll \(input.roll) Pitch \(input.pitch)"
        case .balanceBoard(let input):
            return "Raw weight \(input.sensors.total)"
        case .tatacon(let input):
            return input.buttons.labels.isEmpty ? "No hits" : input.buttons.labels.joined(separator: "+")
        case .raw(let kind, let bytes):
            return "\(kind.displayName) · \(bytes.count) raw bytes"
        }
    }
}

struct WiimoteNunchukInput: Equatable, Sendable {
    let stickX: UInt8
    let stickY: UInt8
    let acceleration: WiimoteAcceleration
    let cPressed: Bool
    let zPressed: Bool

    init?(bytes: [UInt8]) {
        guard bytes.count >= 6 else { return nil }
        self.stickX = bytes[0]
        self.stickY = bytes[1]
        self.acceleration = WiimoteAcceleration(
            rawX: (UInt16(bytes[2]) << 2) | UInt16((bytes[5] >> 2) & 0x03),
            rawY: (UInt16(bytes[3]) << 2) | UInt16((bytes[5] >> 4) & 0x03),
            rawZ: (UInt16(bytes[4]) << 2) | UInt16((bytes[5] >> 6) & 0x03)
        )
        self.cPressed = (bytes[5] & 0x02) == 0
        self.zPressed = (bytes[5] & 0x01) == 0
    }

    init?(passthroughBytes bytes: [UInt8]) {
        guard bytes.count >= 6 else { return nil }
        self.stickX = bytes[0]
        self.stickY = bytes[1]
        self.acceleration = WiimoteAcceleration(
            rawX: (UInt16(bytes[2]) << 2) | UInt16((bytes[5] >> 3) & 0x02),
            rawY: (UInt16(bytes[3]) << 2) | UInt16((bytes[5] >> 4) & 0x02),
            rawZ: (UInt16(bytes[4] & 0xFE) << 2) | UInt16((bytes[5] >> 5) & 0x06)
        )
        self.cPressed = (bytes[5] & 0x08) == 0
        self.zPressed = (bytes[5] & 0x04) == 0
    }
}

struct WiimoteClassicButtons: OptionSet, Hashable, Sendable {
    let rawValue: UInt16

    static let dpadRight = WiimoteClassicButtons(rawValue: 1 << 0)
    static let dpadDown = WiimoteClassicButtons(rawValue: 1 << 1)
    static let leftTriggerClick = WiimoteClassicButtons(rawValue: 1 << 2)
    static let minus = WiimoteClassicButtons(rawValue: 1 << 3)
    static let home = WiimoteClassicButtons(rawValue: 1 << 4)
    static let plus = WiimoteClassicButtons(rawValue: 1 << 5)
    static let rightTriggerClick = WiimoteClassicButtons(rawValue: 1 << 6)
    static let zl = WiimoteClassicButtons(rawValue: 1 << 7)
    static let b = WiimoteClassicButtons(rawValue: 1 << 8)
    static let y = WiimoteClassicButtons(rawValue: 1 << 9)
    static let a = WiimoteClassicButtons(rawValue: 1 << 10)
    static let x = WiimoteClassicButtons(rawValue: 1 << 11)
    static let zr = WiimoteClassicButtons(rawValue: 1 << 12)
    static let dpadLeft = WiimoteClassicButtons(rawValue: 1 << 13)
    static let dpadUp = WiimoteClassicButtons(rawValue: 1 << 14)

    var labels: [String] {
        let ordered: [(WiimoteClassicButtons, String)] = [
            (.dpadUp, "Up"), (.dpadDown, "Down"), (.dpadLeft, "Left"), (.dpadRight, "Right"),
            (.a, "A"), (.b, "B"), (.x, "X"), (.y, "Y"),
            (.zl, "ZL"), (.zr, "ZR"), (.leftTriggerClick, "L"), (.rightTriggerClick, "R"),
            (.plus, "+"), (.minus, "-"), (.home, "Home")
        ]
        return ordered.compactMap { contains($0.0) ? $0.1 : nil }
    }
}

struct WiimoteClassicControllerInput: Equatable, Sendable {
    let leftX: UInt16
    let leftY: UInt16
    let rightX: UInt16
    let rightY: UInt16
    let leftTrigger: UInt16
    let rightTrigger: UInt16
    let buttons: WiimoteClassicButtons

    init?(bytes: [UInt8]) {
        guard bytes.count >= 6 else { return nil }
        self.leftX = UInt16(bytes[0] & 0x3F)
        self.leftY = UInt16(bytes[1] & 0x3F)
        self.rightX = UInt16((bytes[0] >> 3) & 0x18) |
            UInt16((bytes[1] >> 5) & 0x06) |
            UInt16((bytes[2] >> 7) & 0x01)
        self.rightY = UInt16(bytes[2] & 0x1F)
        self.leftTrigger = UInt16((bytes[2] >> 2) & 0x18) | UInt16(bytes[3] >> 5)
        self.rightTrigger = UInt16(bytes[3] & 0x1F)
        self.buttons = WiimoteClassicControllerInput.parseButtons(byte4: bytes[4], byte5: bytes[5])
    }

    init?(passthroughBytes bytes: [UInt8]) {
        guard bytes.count >= 6 else { return nil }
        self.leftX = UInt16(bytes[0] & 0x3E)
        self.leftY = UInt16(bytes[1] & 0x3E)
        self.rightX = UInt16((bytes[0] >> 3) & 0x18) |
            UInt16((bytes[1] >> 5) & 0x06) |
            UInt16((bytes[2] >> 7) & 0x01)
        self.rightY = UInt16(bytes[2] & 0x1F)
        self.leftTrigger = UInt16((bytes[2] >> 2) & 0x18) | UInt16(bytes[3] >> 5)
        self.rightTrigger = UInt16(bytes[3] & 0x1F)
        var buttons = WiimoteClassicControllerInput.parseButtons(byte4: bytes[4], byte5: bytes[5])
        if (bytes[0] & 0x01) == 0 { buttons.insert(.dpadUp) }
        if (bytes[1] & 0x01) == 0 { buttons.insert(.dpadLeft) }
        self.buttons = buttons
    }

    private static func parseButtons(byte4: UInt8, byte5: UInt8) -> WiimoteClassicButtons {
        var buttons: WiimoteClassicButtons = []
        if (byte4 & 0x80) == 0 { buttons.insert(.dpadRight) }
        if (byte4 & 0x40) == 0 { buttons.insert(.dpadDown) }
        if (byte4 & 0x20) == 0 { buttons.insert(.leftTriggerClick) }
        if (byte4 & 0x10) == 0 { buttons.insert(.minus) }
        if (byte4 & 0x08) == 0 { buttons.insert(.home) }
        if (byte4 & 0x04) == 0 { buttons.insert(.plus) }
        if (byte4 & 0x02) == 0 { buttons.insert(.rightTriggerClick) }
        if (byte5 & 0x80) == 0 { buttons.insert(.zl) }
        if (byte5 & 0x40) == 0 { buttons.insert(.b) }
        if (byte5 & 0x20) == 0 { buttons.insert(.y) }
        if (byte5 & 0x10) == 0 { buttons.insert(.a) }
        if (byte5 & 0x08) == 0 { buttons.insert(.x) }
        if (byte5 & 0x04) == 0 { buttons.insert(.zr) }
        if (byte5 & 0x02) == 0 { buttons.insert(.dpadLeft) }
        if (byte5 & 0x01) == 0 { buttons.insert(.dpadUp) }
        return buttons
    }
}

struct WiimoteGuitarButtons: OptionSet, Hashable, Sendable {
    let rawValue: UInt16

    static let strumUp = WiimoteGuitarButtons(rawValue: 0x0001)
    static let yellow = WiimoteGuitarButtons(rawValue: 0x0008)
    static let green = WiimoteGuitarButtons(rawValue: 0x0010)
    static let blue = WiimoteGuitarButtons(rawValue: 0x0020)
    static let red = WiimoteGuitarButtons(rawValue: 0x0040)
    static let orange = WiimoteGuitarButtons(rawValue: 0x0080)
    static let plus = WiimoteGuitarButtons(rawValue: 0x0400)
    static let minus = WiimoteGuitarButtons(rawValue: 0x1000)
    static let strumDown = WiimoteGuitarButtons(rawValue: 0x4000)
    static let buttonMask: UInt16 = 0xFEFF

    var labels: [String] {
        let ordered: [(WiimoteGuitarButtons, String)] = [
            (.green, "Green"), (.red, "Red"), (.yellow, "Yellow"), (.blue, "Blue"), (.orange, "Orange"),
            (.strumUp, "Strum Up"), (.strumDown, "Strum Down"),
            (.plus, "+"), (.minus, "-")
        ]
        return ordered.compactMap { contains($0.0) ? $0.1 : nil }
    }
}

struct WiimoteGuitarInput: Equatable, Sendable {
    let stickX: UInt8
    let stickY: UInt8
    let whammyRaw: UInt8
    let whammy: Double
    let buttons: WiimoteGuitarButtons

    var whammyPercent: Int {
        Int((whammy * 100).rounded())
    }

    init?(bytes: [UInt8]) {
        guard bytes.count >= 6 else { return nil }
        self.stickX = bytes[0]
        self.stickY = bytes[1]
        self.whammyRaw = bytes[3]
        self.whammy = ((Double(bytes[3]) - 0xEF) / Double(0xFA - 0xEF)).clamped(to: 0...1)
        let activeLowButtons = ~((UInt16(bytes[4]) << 8) | UInt16(bytes[5]))
        self.buttons = WiimoteGuitarButtons(rawValue: activeLowButtons & WiimoteGuitarButtons.buttonMask)
    }
}

struct WiimoteTataconButtons: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    static let centerLeft = WiimoteTataconButtons(rawValue: 0x40)
    static let centerRight = WiimoteTataconButtons(rawValue: 0x10)
    static let rimLeft = WiimoteTataconButtons(rawValue: 0x20)
    static let rimRight = WiimoteTataconButtons(rawValue: 0x08)
    static let buttonMask: UInt8 = 0x78

    var labels: [String] {
        let ordered: [(WiimoteTataconButtons, String)] = [
            (.centerLeft, "Center Left"), (.centerRight, "Center Right"),
            (.rimLeft, "Rim Left"), (.rimRight, "Rim Right")
        ]
        return ordered.compactMap { contains($0.0) ? $0.1 : nil }
    }
}

struct WiimoteTataconInput: Equatable, Sendable {
    let buttons: WiimoteTataconButtons

    init?(bytes: [UInt8]) {
        guard bytes.count >= 6 else { return nil }
        self.buttons = WiimoteTataconButtons(rawValue: (~bytes[5]) & WiimoteTataconButtons.buttonMask)
    }
}

struct WiimoteMotionPlusInput: Equatable, Sendable {
    let yaw: UInt16
    let roll: UInt16
    let pitch: UInt16
    let yawSlowMode: Bool
    let rollSlowMode: Bool
    let pitchSlowMode: Bool
    let passthroughExtensionConnected: Bool

    init?(bytes: [UInt8]) {
        guard bytes.count >= 6 else { return nil }
        self.yaw = UInt16(bytes[0]) | (UInt16(bytes[3] & 0xFC) << 6)
        self.roll = UInt16(bytes[1]) | (UInt16(bytes[4] & 0xFC) << 6)
        self.pitch = UInt16(bytes[2]) | (UInt16(bytes[5] & 0xFC) << 6)
        self.yawSlowMode = (bytes[3] & 0x02) != 0
        self.pitchSlowMode = (bytes[3] & 0x01) != 0
        self.rollSlowMode = (bytes[4] & 0x02) != 0
        self.passthroughExtensionConnected = (bytes[4] & 0x01) != 0
    }

    static func isMotionPlusPacket(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 6 else { return false }
        return (bytes[5] & 0x03) == 0x02
    }
}

struct WiimoteMotionPlusGyroscope: Equatable, Sendable {
    let rawYaw: UInt16
    let rawRoll: UInt16
    let rawPitch: UInt16
    let yawDegreesPerSecond: Double
    let rollDegreesPerSecond: Double
    let pitchDegreesPerSecond: Double
    let yawSlowMode: Bool
    let rollSlowMode: Bool
    let pitchSlowMode: Bool
}

struct WiimoteBalanceBoardSensors: Equatable, Sendable {
    let topRight: UInt16
    let bottomRight: UInt16
    let topLeft: UInt16
    let bottomLeft: UInt16

    var total: UInt32 {
        UInt32(topRight) + UInt32(bottomRight) + UInt32(topLeft) + UInt32(bottomLeft)
    }
}

struct WiimoteBalanceBoardInput: Equatable, Sendable {
    let sensors: WiimoteBalanceBoardSensors
    let temperature: UInt8
    let batteryRaw: UInt8

    init?(bytes: [UInt8]) {
        guard bytes.count >= 11 else { return nil }
        self.sensors = WiimoteBalanceBoardSensors(
            topRight: Self.bigEndian(bytes[0], bytes[1]),
            bottomRight: Self.bigEndian(bytes[2], bytes[3]),
            topLeft: Self.bigEndian(bytes[4], bytes[5]),
            bottomLeft: Self.bigEndian(bytes[6], bytes[7])
        )
        self.temperature = bytes[8]
        self.batteryRaw = bytes[10]
    }

    private static func bigEndian(_ high: UInt8, _ low: UInt8) -> UInt16 {
        (UInt16(high) << 8) | UInt16(low)
    }
}

struct WiimoteBalanceBoardWeight: Equatable, Sendable {
    let topRightKilograms: Double
    let bottomRightKilograms: Double
    let topLeftKilograms: Double
    let bottomLeftKilograms: Double

    var totalKilograms: Double {
        topRightKilograms + bottomRightKilograms + topLeftKilograms + bottomLeftKilograms
    }
}

struct WiimoteBalanceBoardCalibration: Equatable, Sendable {
    let zeroKilograms: WiimoteBalanceBoardSensors
    let seventeenKilograms: WiimoteBalanceBoardSensors
    let thirtyFourKilograms: WiimoteBalanceBoardSensors
    let checksum: UInt32
    let referenceTemperature: UInt8?

    init?(bytes: [UInt8], referenceTemperature: UInt8? = nil) {
        guard bytes.count >= 32 else { return nil }
        self.zeroKilograms = Self.sensors(bytes, offset: 4)
        self.seventeenKilograms = Self.sensors(bytes, offset: 12)
        self.thirtyFourKilograms = Self.sensors(bytes, offset: 20)
        self.checksum = (UInt32(bytes[28]) << 24) |
            (UInt32(bytes[29]) << 16) |
            (UInt32(bytes[30]) << 8) |
            UInt32(bytes[31])
        self.referenceTemperature = referenceTemperature
    }

    func weight(for input: WiimoteBalanceBoardInput) -> WiimoteBalanceBoardWeight {
        WiimoteBalanceBoardWeight(
            topRightKilograms: kilograms(
                raw: input.sensors.topRight,
                zero: zeroKilograms.topRight,
                middle: seventeenKilograms.topRight,
                high: thirtyFourKilograms.topRight
            ),
            bottomRightKilograms: kilograms(
                raw: input.sensors.bottomRight,
                zero: zeroKilograms.bottomRight,
                middle: seventeenKilograms.bottomRight,
                high: thirtyFourKilograms.bottomRight
            ),
            topLeftKilograms: kilograms(
                raw: input.sensors.topLeft,
                zero: zeroKilograms.topLeft,
                middle: seventeenKilograms.topLeft,
                high: thirtyFourKilograms.topLeft
            ),
            bottomLeftKilograms: kilograms(
                raw: input.sensors.bottomLeft,
                zero: zeroKilograms.bottomLeft,
                middle: seventeenKilograms.bottomLeft,
                high: thirtyFourKilograms.bottomLeft
            )
        )
    }

    private func kilograms(raw: UInt16, zero: UInt16, middle: UInt16, high: UInt16) -> Double {
        if raw <= middle {
            return interpolate(raw: raw, lowRaw: zero, highRaw: middle, lowKg: 0, highKg: 17)
        }
        return interpolate(raw: raw, lowRaw: middle, highRaw: high, lowKg: 17, highKg: 34)
    }

    private func interpolate(
        raw: UInt16,
        lowRaw: UInt16,
        highRaw: UInt16,
        lowKg: Double,
        highKg: Double
    ) -> Double {
        let span = max(1.0, Double(highRaw) - Double(lowRaw))
        let fraction = (Double(raw) - Double(lowRaw)) / span
        return lowKg + fraction * (highKg - lowKg)
    }

    private static func sensors(_ bytes: [UInt8], offset: Int) -> WiimoteBalanceBoardSensors {
        WiimoteBalanceBoardSensors(
            topRight: bigEndian(bytes[offset], bytes[offset + 1]),
            bottomRight: bigEndian(bytes[offset + 2], bytes[offset + 3]),
            topLeft: bigEndian(bytes[offset + 4], bytes[offset + 5]),
            bottomLeft: bigEndian(bytes[offset + 6], bytes[offset + 7])
        )
    }

    private static func bigEndian(_ high: UInt8, _ low: UInt8) -> UInt16 {
        (UInt16(high) << 8) | UInt16(low)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
