import Foundation

enum ControllerProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case sideways
    case upright

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sideways: return "Sideways Wii Remote"
        case .upright: return "Upright Wii Remote"
        }
    }

    var detail: String {
        switch self {
        case .sideways: return "Rotates the D-pad and maps 2/1 as the primary face buttons."
        case .upright: return "Keeps the D-pad orientation and maps A/B as the primary buttons."
        }
    }
}

enum MotionInputSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case accelerometer
    case motionPlusGyro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .accelerometer: return "Accelerometer"
        case .motionPlusGyro: return "MotionPlus Gyro"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Uses MotionPlus yaw/pitch when available, otherwise falls back to Wii Remote accelerometer tilt."
        case .accelerometer:
            return "Uses Wii Remote accelerometer tilt, matching the existing motion-right-stick behavior."
        case .motionPlusGyro:
            return "Uses MotionPlus or Wii Remote Plus gyroscope axes, so motion input can work without a sensor bar."
        }
    }
}

struct VirtualGamepadState: Equatable, Sendable {
    var leftX: Int8 = 0
    var leftY: Int8 = 0
    var rightX: Int8 = 0
    var rightY: Int8 = 0
    var hat: UInt8 = 8
    var buttons: UInt16 = 0

    static let neutral = VirtualGamepadState()
}

enum ControllerTransportKind: Equatable, Sendable {
    case unknown
    case usb
    case bluetooth
}

struct ControllerMotionState: Equatable, Sendable {
    var accelerationXG: Double = 0
    var accelerationYG: Double = 0
    var accelerationZG: Double = 0
    var gyroPitchDegreesPerSecond: Double = 0
    var gyroYawDegreesPerSecond: Double = 0
    var gyroRollDegreesPerSecond: Double = 0

    static let neutral = ControllerMotionState()
}

struct ControllerRuntimeSnapshot: Identifiable, Equatable, Sendable {
    let id: UInt64
    let slot: Int
    let name: String
    let address: String?
    let batteryPercent: Int?
    let transport: ControllerTransportKind
    let gamepadState: VirtualGamepadState
    let motion: ControllerMotionState
    let hasFullGyro: Bool
}

enum VirtualGamepadButton: Int, Sendable {
    case south = 0
    case east
    case west
    case north
    case leftShoulder
    case rightShoulder
    case leftTrigger
    case select
    case start
    case home
    case rightTrigger
    case leftStick
    case rightStick
    case auxiliary1
    case auxiliary2
    case auxiliary3

    var mask: UInt16 { UInt16(1) << UInt16(rawValue) }
}

enum GamepadMapper {
    static func map(
        buttons: WiimoteButtons,
        extensionInput: WiimoteExtensionInput?,
        profile: ControllerProfile,
        motionRightStick: (x: Int8, y: Int8)?
    ) -> VirtualGamepadState {
        var result = map(buttons: buttons, profile: profile, motionRightStick: motionRightStick)
        apply(extensionInput: extensionInput, to: &result)
        return result
    }

    static func map(
        buttons: WiimoteButtons,
        profile: ControllerProfile,
        motionRightStick: (x: Int8, y: Int8)?
    ) -> VirtualGamepadState {
        let directions = mappedDirections(buttons: buttons, profile: profile)
        var result = VirtualGamepadState()

        result.leftX = directions.left ? -127 : (directions.right ? 127 : 0)
        result.leftY = directions.up ? -127 : (directions.down ? 127 : 0)
        result.hat = hatValue(
            up: directions.up,
            down: directions.down,
            left: directions.left,
            right: directions.right
        )

        if let motionRightStick {
            result.rightX = motionRightStick.x
            result.rightY = motionRightStick.y
        }

        switch profile {
        case .sideways:
            set(.south, when: buttons.contains(.two), in: &result)
            set(.east, when: buttons.contains(.one), in: &result)
            set(.west, when: buttons.contains(.b), in: &result)
            set(.north, when: buttons.contains(.a), in: &result)

        case .upright:
            set(.south, when: buttons.contains(.a), in: &result)
            set(.east, when: buttons.contains(.b), in: &result)
            set(.west, when: buttons.contains(.one), in: &result)
            set(.north, when: buttons.contains(.two), in: &result)
        }

        set(.start, when: buttons.contains(.plus), in: &result)
        set(.select, when: buttons.contains(.minus), in: &result)
        set(.home, when: buttons.contains(.home), in: &result)
        return result
    }

    private static func mappedDirections(
        buttons: WiimoteButtons,
        profile: ControllerProfile
    ) -> (up: Bool, down: Bool, left: Bool, right: Bool) {
        switch profile {
        case .upright:
            return (
                buttons.contains(.dpadUp),
                buttons.contains(.dpadDown),
                buttons.contains(.dpadLeft),
                buttons.contains(.dpadRight)
            )

        case .sideways:
            // Rotate clockwise so the infrared end points to the user's left.
            return (
                buttons.contains(.dpadRight),
                buttons.contains(.dpadLeft),
                buttons.contains(.dpadUp),
                buttons.contains(.dpadDown)
            )
        }
    }

    private static func set(
        _ button: VirtualGamepadButton,
        when condition: Bool,
        in state: inout VirtualGamepadState
    ) {
        if condition { state.buttons |= button.mask }
    }

    private static func apply(extensionInput: WiimoteExtensionInput?, to state: inout VirtualGamepadState) {
        switch extensionInput {
        case .nunchuk(let nunchuk):
            state.leftX = signedStickAxis(nunchuk.stickX, center: 128, range: 127)
            state.leftY = signedStickAxis(nunchuk.stickY, center: 128, range: 127, inverted: true)
            set(.leftShoulder, when: nunchuk.cPressed, in: &state)
            set(.leftTrigger, when: nunchuk.zPressed, in: &state)

        case .classicController(let classic):
            state.leftX = signedStickAxis(classic.leftX, center: 32, range: 31)
            state.leftY = signedStickAxis(classic.leftY, center: 32, range: 31, inverted: true)
            state.rightX = signedStickAxis(classic.rightX, center: 16, range: 15)
            state.rightY = signedStickAxis(classic.rightY, center: 16, range: 15, inverted: true)
            state.hat = hatValue(
                up: classic.buttons.contains(.dpadUp),
                down: classic.buttons.contains(.dpadDown),
                left: classic.buttons.contains(.dpadLeft),
                right: classic.buttons.contains(.dpadRight)
            )
            set(.south, when: classic.buttons.contains(.b), in: &state)
            set(.east, when: classic.buttons.contains(.a), in: &state)
            set(.west, when: classic.buttons.contains(.y), in: &state)
            set(.north, when: classic.buttons.contains(.x), in: &state)
            set(.leftShoulder, when: classic.buttons.contains(.leftTriggerClick), in: &state)
            set(.rightShoulder, when: classic.buttons.contains(.rightTriggerClick), in: &state)
            set(.leftTrigger, when: classic.buttons.contains(.zl), in: &state)
            set(.rightTrigger, when: classic.buttons.contains(.zr), in: &state)
            set(.select, when: classic.buttons.contains(.minus), in: &state)
            set(.start, when: classic.buttons.contains(.plus), in: &state)
            set(.home, when: classic.buttons.contains(.home), in: &state)

        case .guitar(let guitar):
            state.leftX = signedStickAxis(guitar.stickX, center: 128, range: 127)
            state.leftY = signedStickAxis(guitar.stickY, center: 128, range: 127, inverted: true)
            state.hat = hatValue(
                up: guitar.buttons.contains(.strumUp),
                down: guitar.buttons.contains(.strumDown),
                left: false,
                right: false
            )
            set(.south, when: guitar.buttons.contains(.green), in: &state)
            set(.east, when: guitar.buttons.contains(.red), in: &state)
            set(.west, when: guitar.buttons.contains(.yellow), in: &state)
            set(.north, when: guitar.buttons.contains(.blue), in: &state)
            set(.rightShoulder, when: guitar.buttons.contains(.orange), in: &state)
            set(.select, when: guitar.buttons.contains(.minus), in: &state)
            set(.start, when: guitar.buttons.contains(.plus), in: &state)

        case .tatacon(let tatacon):
            set(.south, when: tatacon.buttons.contains(.centerLeft), in: &state)
            set(.east, when: tatacon.buttons.contains(.centerRight), in: &state)
            set(.west, when: tatacon.buttons.contains(.rimLeft), in: &state)
            set(.north, when: tatacon.buttons.contains(.rimRight), in: &state)

        case .motionPlus, .balanceBoard, .raw, .none:
            break
        }
    }

    private static func signedStickAxis<T: BinaryInteger>(
        _ value: T,
        center: Double,
        range: Double,
        inverted: Bool = false
    ) -> Int8 {
        let rawNormalized = (Double(Int(value)) - center) / range
        let normalized = min(max(rawNormalized, -1), 1)
        let scaled = Int((normalized * 127).rounded())
        return Int8(clamping: inverted ? -scaled : scaled)
    }

    private static func hatValue(
        up: Bool,
        down: Bool,
        left: Bool,
        right: Bool
    ) -> UInt8 {
        if up {
            if right { return 1 }
            if left { return 7 }
            return 0
        }
        if down {
            if right { return 3 }
            if left { return 5 }
            return 4
        }
        if right { return 2 }
        if left { return 6 }
        return 8
    }
}
