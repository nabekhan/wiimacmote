import Foundation

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
    let extensionData: [UInt8]
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

enum WiimotePacket: Equatable, Sendable {
    case input(WiimoteInput)
    case status(WiimoteStatus)
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

        case 0x22:
            guard bytes.count >= 5 else { return nil }
            return .acknowledgment(reportID: bytes[3], error: bytes[4])

        case 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x3D:
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
                    extensionData: Array(bytes[1..<22])
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

        return .input(
            WiimoteInput(
                reportID: reportID,
                buttons: buttons,
                acceleration: acceleration,
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

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
