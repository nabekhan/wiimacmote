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
        try testExtensionReport()
        try testMalformedAndInterleavedReports()
        try testUprightMapping()
        try testSidewaysMapping()
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

    private static func testExtensionReport() throws {
        let payload = Array(UInt8(0)...UInt8(18))
        let packet = WiimoteReportParser.parse(Data([0x34, 0x00, 0x00] + payload))
        guard case .input(let input) = packet else {
            throw TestFailure.failed("0x34 report was not parsed as extension input")
        }
        try expect(input.extensionData == payload, "0x34 extension payload was sliced incorrectly")
    }

    private static func testMalformedAndInterleavedReports() throws {
        try expect(
            WiimoteReportParser.parse(Data([0x31, 0x00, 0x00])) == nil,
            "A truncated accelerometer report must be rejected"
        )
        guard case .ignored(let reportID) = WiimoteReportParser.parse(Data([0x3E, 0x00, 0x00])) else {
            throw TestFailure.failed("Interleaved 0x3E mode must remain explicitly unsupported")
        }
        try expect(reportID == 0x3E, "Ignored report ID should be preserved")
    }

    private static func testUprightMapping() throws {
        let state = GamepadMapper.map(
            buttons: [.dpadUp, .dpadRight, .a, .plus],
            profile: .upright,
            motionRightStick: nil
        )
        try expect(state.leftX == 127 && state.leftY == -127, "Upright axes are wrong")
        try expect(state.hat == 1, "Up-right hat should be 1")
        try expect((state.buttons & VirtualGamepadButton.south.mask) != 0, "A should map south")
        try expect((state.buttons & VirtualGamepadButton.start.mask) != 0, "+ should map start")
    }

    private static func testSidewaysMapping() throws {
        let state = GamepadMapper.map(
            buttons: [.dpadRight, .two, .minus],
            profile: .sideways,
            motionRightStick: (x: 42, y: -17)
        )
        try expect(state.leftY == -127, "Physical right should become up in sideways mode")
        try expect(state.hat == 0, "Sideways rotated hat should be up")
        try expect(state.rightX == 42 && state.rightY == -17, "Motion stick should pass through")
        try expect((state.buttons & VirtualGamepadButton.south.mask) != 0, "2 should map south")
        try expect((state.buttons & VirtualGamepadButton.select.mask) != 0, "- should map select")
    }
}
