import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) throws {
    if !condition() { throw TestFailure.failed(message) }
}

@main
struct CoreTests {
    static func main() throws {
        try testButtonsReport()
        try testStatusReport()
        try testAccelerationReport()
        try testAcknowledgementReport()
        try testReadMemoryReport()
        try testOutputReportBuilders()
        try testIRReport()
        try testExtensionReport()
        try testExtensionDecoders()
        try testWiiuseExtensionIdentifiers()
        try testWiiuseExtensionInputs()
        try testCalibrationDecoders()
        try testMalformedAndInterleavedReports()
        print("All WiiMacMote core tests passed.")
    }

    private static func testButtonsReport() throws {
        let packet = WiimoteReportParser.parse(Data([0x30, 0x09, 0x0C]))
        guard case .input(let input) = packet else {
            throw TestFailure.failed("0x30 report was not parsed as input")
        }
        try expect(input.buttons.contains(.dpadLeft), "Left should be pressed")
        try expect(input.buttons.contains(.dpadUp), "Up should be pressed")
        try expect(input.buttons.contains(.a), "A should be pressed")
        try expect(input.buttons.contains(.b), "B should be pressed")
        try expect(input.acceleration == nil, "0x30 must not contain acceleration")
    }

    private static func testStatusReport() throws {
        let packet = WiimoteReportParser.parse(
            Data([0x20, 0x08, 0x08, 0x92, 0x00, 0x00, 0x80])
        )
        guard case .status(let status) = packet else {
            throw TestFailure.failed("0x20 report was not parsed as status")
        }
        try expect(status.buttons.contains(.dpadUp), "Status should preserve buttons")
        try expect(status.buttons.contains(.a), "Status should preserve A")
        try expect(status.extensionConnected, "Extension flag should be set")
        try expect(status.ledMask == 0x90, "LED mask should preserve LEDs 1 and 4")
        try expect(status.batteryPercent == 50, "0x80 battery should round to 50%")
    }

    private static func testAccelerationReport() throws {
        // High bytes 0x80/0x81/0x7F plus precision bits in button bytes.
        let packet = WiimoteReportParser.parse(
            Data([0x31, 0x60, 0x60, 0x80, 0x81, 0x7F])
        )
        guard case .input(let input) = packet,
              let acceleration = input.acceleration else {
            throw TestFailure.failed("0x31 report was not parsed with acceleration")
        }
        try expect(acceleration.rawX == 515, "Unexpected 10-bit X value")
        try expect(acceleration.rawY == 518, "Unexpected 9-bit Y value in 10-bit space")
        try expect(acceleration.rawZ == 510, "Unexpected 9-bit Z value in 10-bit space")
        try expect(input.buttons.isEmpty, "Accelerometer precision bits are not buttons")
    }


    private static func testAcknowledgementReport() throws {
        let packet = WiimoteReportParser.parse(Data([0x22, 0x00, 0x00, 0x12, 0x00]))
        guard case .acknowledgment(let reportID, let error) = packet else {
            throw TestFailure.failed("0x22 report was not parsed as an acknowledgement")
        }
        try expect(reportID == 0x12, "Acknowledged report ID should be preserved")
        try expect(error == 0x00, "Acknowledgement error should be preserved")
    }

    private static func testReadMemoryReport() throws {
        let packet = WiimoteReportParser.parse(
            Data([0x21, 0x00, 0x00, 0x20, 0x00, 0xFA, 0x01, 0x02, 0x03] + Array(repeating: 0, count: 13))
        )
        guard case .readData(let read) = packet else {
            throw TestFailure.failed("0x21 report was not parsed as read data")
        }
        try expect(read.size == 3, "Read size should come from the high nibble")
        try expect(read.error == 0, "Read error should come from the low nibble")
        try expect(read.offsetLow == 0x00FA, "Read offset low word is wrong")
        try expect(read.data == [0x01, 0x02, 0x03], "Read data should trim padding")
    }

    private static func testOutputReportBuilders() throws {
        let write = WiimoteOutputReports.writeMemory(
            addressSpace: .register,
            address: 0xA4_00_F0,
            bytes: [0x55]
        )
        try expect(write?.reportID == 0x16, "Write-memory report ID is wrong")
        try expect(write?.payload.count == 21, "Write-memory payload must be padded to 21 bytes")
        try expect(Array(write?.payload.prefix(6) ?? []) == [0x04, 0xA4, 0x00, 0xF0, 0x01, 0x55], "Write-memory payload is wrong")

        let read = WiimoteOutputReports.readMemory(
            addressSpace: .eeprom,
            address: 0x00_00_16,
            length: 10
        )
        try expect(read?.reportID == 0x17, "Read-memory report ID is wrong")
        try expect(read?.payload == [0x00, 0x00, 0x00, 0x16, 0x00, 0x0A], "Read-memory payload is wrong")

        let speaker = WiimoteOutputReports.speakerData([0xAA, 0xBB])
        try expect(speaker?.reportID == 0x18, "Speaker-data report ID is wrong")
        try expect(speaker?.payload[0] == 0x10, "Speaker-data length nibble is wrong")

        let motionPlus = WiimoteOutputReports.motionPlusActivate(mode: .standalone)
        try expect(motionPlus?.reportID == 0x16, "MotionPlus activation should be a write-memory report")
        try expect(
            Array(motionPlus?.payload.prefix(6) ?? []) == [0x04, 0xA6, 0x00, 0xFE, 0x01, 0x04],
            "MotionPlus standalone activation payload is wrong"
        )
    }

    private static func testIRReport() throws {
        let ir: [UInt8] = [
            0x23, 0x34, 0x95,
            0xFF, 0xFF, 0xFF,
            0xFF, 0xFF, 0xFF,
            0xFF, 0xFF, 0xFF
        ]
        let packet = WiimoteReportParser.parse(Data([0x33, 0x00, 0x00, 0x80, 0x80, 0x80] + ir))
        guard case .input(let input) = packet else {
            throw TestFailure.failed("0x33 report was not parsed as input")
        }
        try expect(input.irData == ir, "IR payload was sliced incorrectly")
        try expect(input.irPoints.count == 1, "Only one IR point should be visible")
        try expect(input.irPoints[0].x == 0x123, "IR X coordinate is wrong")
        try expect(input.irPoints[0].y == 0x234, "IR Y coordinate is wrong")
        try expect(input.irPoints[0].size == 5, "IR size is wrong")

        let nunchukBytes: [UInt8] = [0x80, 0x7F, 0x80, 0x81, 0x7F, 0xAC]
        let packetWithExtension = WiimoteReportParser.parse(
            Data([0x37, 0x00, 0x00, 0x80, 0x80, 0x80] + Array(repeating: 0xFF, count: 10) + nunchukBytes)
        )
        guard case .input(let inputWithExtension) = packetWithExtension else {
            throw TestFailure.failed("0x37 report was not parsed as input")
        }
        try expect(inputWithExtension.irData.count == 10, "0x37 IR payload should use basic 10-byte IR data")
        try expect(inputWithExtension.extensionData == nunchukBytes, "0x37 extension payload should preserve exact Nunchuk bytes")
        try expect(WiimoteNunchukInput(bytes: inputWithExtension.extensionData) != nil, "0x37 Nunchuk payload should decode")

        let basicIRSequence = WiimoteOutputReports.irInitializationSequence(mode: .basic)
        try expect(
            basicIRSequence.contains { Array($0.payload.prefix(6)) == [0x04, 0xB0, 0x00, 0x33, 0x01, WiimoteIRMode.basic.rawValue] },
            "Basic IR initialization should write basic mode"
        )

        let fullIR = Array(ir.prefix(3)) + Array(repeating: 0, count: 6) + Array(ir.prefix(3)) + Array(repeating: 0, count: 6)
        try expect(WiimoteIRPoint.parse(fullIR).count == 2, "Full/interleaved IR objects should parse coordinates")
    }

    private static func testExtensionReport() throws {
        let payload = Array(UInt8(0)...UInt8(18))
        let packet = WiimoteReportParser.parse(Data([0x34, 0x00, 0x00] + payload))
        guard case .input(let input) = packet else {
            throw TestFailure.failed("0x34 report was not parsed as extension input")
        }
        try expect(input.extensionData == payload, "0x34 extension payload was sliced incorrectly")
    }

    private static func testExtensionDecoders() throws {
        let kind = WiimoteExtensionKind(identifier: [0x00, 0x00, 0xA4, 0x20, 0x00, 0x00])
        try expect(kind == .nunchuk, "Nunchuk identifier should be recognized")

        let nunchuk = WiimoteNunchukInput(bytes: [0x80, 0x7F, 0x80, 0x81, 0x7F, 0xAC])
        try expect(nunchuk?.stickX == 0x80 && nunchuk?.stickY == 0x7F, "Nunchuk stick decode is wrong")
        try expect(nunchuk?.acceleration.rawX == 515, "Nunchuk X acceleration is wrong")
        try expect(nunchuk?.acceleration.rawY == 518, "Nunchuk Y acceleration is wrong")
        try expect(nunchuk?.acceleration.rawZ == 510, "Nunchuk Z acceleration is wrong")
        try expect(nunchuk?.cPressed == true && nunchuk?.zPressed == true, "Nunchuk buttons are active-low")

        let classic = WiimoteClassicControllerInput(bytes: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        try expect(classic?.leftX == 63 && classic?.rightX == 31, "Classic Controller axes are wrong")
        try expect(classic?.buttons.isEmpty == true, "Classic Controller buttons are active-low")

        let motionPlus = WiimoteMotionPlusInput(bytes: [0x7F, 0x7F, 0x7F, 0x7E, 0x7F, 0x7E])
        try expect(motionPlus?.yaw == 0x1F7F, "MotionPlus yaw decode is wrong")
        try expect(WiimoteMotionPlusInput.isMotionPlusPacket([0x7F, 0x7F, 0x7F, 0x7E, 0x7F, 0x7E]), "MotionPlus packet marker should be detected")

        let board = WiimoteBalanceBoardInput(bytes: [0x07, 0xC3, 0x3C, 0xF8, 0x04, 0x8C, 0x29, 0x6B, 0x1A, 0x00, 0x80])
        try expect(board?.sensors.topRight == 0x07C3, "Balance Board top-right sensor is wrong")
        try expect(board?.sensors.total == 0x07C3 + 0x3CF8 + 0x048C + 0x296B, "Balance Board raw total is wrong")
    }

    private static func testWiiuseExtensionIdentifiers() throws {
        try expect(
            WiimoteRemoteKind(name: "Nintendo RVL-CNT-01-TR", productID: 0x0330) == .motionPlusInside,
            "RVL-CNT-01-TR should be classified as Wii Remote Plus"
        )
        try expect(
            WiimoteRemoteKind(name: "Nintendo RVL-WBC-01", productID: nil) == .balanceBoard,
            "RVL-WBC-01 should be classified as Balance Board"
        )
        try expect(
            WiimoteMotionPlusCapability(
                identifier: [0x00, 0x00, 0xA4, 0x20, 0x00, 0x05],
                remoteKind: .standard
            ) == .insidePresent,
            "Built-in inactive MotionPlus ID should be recognized"
        )
        try expect(
            WiimoteMotionPlusCapability(
                identifier: [0x00, 0x00, 0xA6, 0x20, 0x00, 0x05],
                remoteKind: .standard
            ) == .accessoryPresent,
            "Accessory inactive MotionPlus ID should be recognized"
        )
        try expect(
            WiimoteMotionPlusCapability(
                identifier: [0x00, 0x00, 0xA6, 0x20, 0x05, 0x05],
                remoteKind: .standard
            ) == .activeNunchukPassthrough,
            "MotionPlus Nunchuk passthrough ID should be recognized"
        )
        try expect(
            WiimoteExtensionKind(identifier: [0x01, 0x00, 0xA6, 0x20, 0x04, 0x05]) == .motionPlusActive,
            "Wiiuse no-longer-active MotionPlus ID should be recognized"
        )
        try expect(
            WiimoteExtensionKind(identifier: [0x01, 0x00, 0xA6, 0x20, 0x05, 0x05]) == .motionPlusNunchukPassthrough,
            "Wiiuse no-longer-active MotionPlus Nunchuk ID should be recognized"
        )
        try expect(
            WiimoteExtensionKind(identifier: [0x01, 0x00, 0xA6, 0x20, 0x07, 0x05]) == .motionPlusClassicPassthrough,
            "Wiiuse no-longer-active MotionPlus Classic ID should be recognized"
        )
        try expect(
            WiimoteExtensionKind(identifier: [0x00, 0x00, 0xA4, 0x20, 0x01, 0x11]) == .tatacon,
            "TaTaCon identifier should be recognized"
        )
        try expect(
            WiimoteExtensionKind.identifierLooksInvalid([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
            "All-FF extension identifiers should trigger a retry"
        )
        try expect(
            WiimoteIdentifierFormatter.hexString([0x00, 0x00, 0xA4, 0x20, 0x01, 0x11]) == "00 00 A4 20 01 11",
            "Extension identifier hex formatting is wrong"
        )
    }

    private static func testWiiuseExtensionInputs() throws {
        let guitar = WiimoteGuitarInput(bytes: [0xE0, 0xE0, 0x00, 0xF4, 0xBB, 0xEF])
        try expect(guitar?.stickX == 0xE0 && guitar?.stickY == 0xE0, "Guitar stick bytes are wrong")
        try expect(guitar?.buttons.contains(.green) == true, "Guitar green fret should be pressed")
        try expect(guitar?.buttons.contains(.plus) == true, "Guitar plus should be pressed")
        try expect(guitar?.buttons.contains(.strumDown) == true, "Guitar strum down should be pressed")
        try expect(guitar?.buttons.contains(.red) == false, "Guitar red fret should be released")
        try expect(guitar?.whammyPercent == 45, "Guitar whammy normalization changed")

        let tatacon = WiimoteTataconInput(bytes: [0, 0, 0, 0, 0, 0xB7])
        try expect(tatacon?.buttons.contains(.centerLeft) == true, "TaTaCon center-left should be pressed")
        try expect(tatacon?.buttons.contains(.rimRight) == true, "TaTaCon rim-right should be pressed")
        try expect(tatacon?.buttons.contains(.rimLeft) == false, "TaTaCon rim-left should be released")
    }

    private static func testCalibrationDecoders() throws {
        let calibrationBytes: [UInt8] = [
            0x10, 0x69, 0x00, 0x00,
            0x07, 0xC3, 0x3C, 0xF8, 0x04, 0x8C, 0x29, 0x6B,
            0x0E, 0xD2, 0x43, 0x84, 0x0B, 0x3A, 0x30, 0x69,
            0x15, 0xE9, 0x4A, 0x10, 0x11, 0xEF, 0x37, 0x6E,
            0x5E, 0x40, 0xE9, 0xB6
        ]
        guard let calibration = WiimoteBalanceBoardCalibration(bytes: calibrationBytes),
              let input = WiimoteBalanceBoardInput(bytes: [0x07, 0xC3, 0x3C, 0xF8, 0x04, 0x8C, 0x29, 0x6B, 0x1A, 0x00, 0x80])
        else {
            throw TestFailure.failed("Balance Board calibration did not parse")
        }
        try expect(abs(calibration.weight(for: input).totalKilograms) < 0.01, "Zero calibration should produce near-zero weight")

        let accelBytes: [UInt8] = [0x80, 0x80, 0x80, 0x00, 0xA0, 0xA0, 0xA0, 0x00, 0x40, 0xF5]
        let accelCalibration = WiimoteAccelerometerCalibration(bytes: accelBytes)
        try expect(accelCalibration?.zero.rawX == 512, "Accelerometer zero decode is wrong")
        try expect(accelCalibration?.oneG.rawX == 640, "Accelerometer one-g decode is wrong")
        try expect(accelCalibration?.checksumValid == true, "Accelerometer checksum is wrong")
    }

    private static func testMalformedAndInterleavedReports() throws {
        try expect(
            WiimoteReportParser.parse(Data([0x31, 0x00, 0x00])) == nil,
            "A truncated accelerometer report must be rejected"
        )
        guard case .input(let input) = WiimoteReportParser.parse(Data([0x3E] + Array(repeating: 0, count: 21))) else {
            throw TestFailure.failed("Interleaved 0x3E mode should parse as input")
        }
        try expect(input.reportID == 0x3E, "Interleaved report ID should be preserved")
        try expect(input.irData.count == 18, "Interleaved IR payload should be preserved")
    }

}
