import Foundation
import IOKit
import IOKit.hid

struct ConnectedWiimoteSnapshot: Identifiable, Equatable {
    let id: UInt64
    let playerIndex: Int
    let name: String
    let address: String?
    let productID: Int
    let remoteKind: WiimoteRemoteKind
    let motionPlusCapability: WiimoteMotionPlusCapability
    let batteryPercent: Int?
    let buttons: [String]
    let gamepadState: VirtualGamepadState
    let acceleration: WiimoteAcceleration?
    let extensionAcceleration: WiimoteAcceleration?
    let motionPlusGyroscope: WiimoteMotionPlusGyroscope?
    let reportsPerSecond: Int
    let reportID: UInt8?
    let extensionConnected: Bool
    let extensionName: String?
    let extensionDetail: String?
    let extensionIdentifier: [UInt8]?
    let extensionIdentifierHex: String?
    let extensionInputSignature: String?
    let irPointCount: Int
    let irPoints: [WiimoteIRPoint]
    let balanceWeightKilograms: Double?
    let virtualGamepadActive: Bool
    let virtualGamepadIdentity: String?
    let virtualGamepadBackend: String?
    let virtualGamepadError: String?
}

struct WiimoteHIDSettings: Equatable {
    var virtualGamepadEnabled: Bool
    var virtualGamepadIdentity: VirtualGamepadIdentity
    var virtualGamepadBackendPreference: VirtualGamepadBackendPreference
    var profile: ControllerProfile
    var motionRightStickEnabled: Bool
    var motionInputSource: MotionInputSource
    var motionPlusEnabled: Bool
    var irCameraEnabled: Bool
    var diagnosticsDSUEnabled: Bool
}

/// Gives C callbacks a stable object whose weak owner can be invalidated
/// before an asynchronous IOHIDManager cancellation has fully drained.
private final class HIDCallbackContext {
    weak var owner: WiimoteHIDController?

    init(owner: WiimoteHIDController) {
        self.owner = owner
    }
}

/// Keeps the dispatch-backed manager and its callback context alive until
/// IOKit has drained its queue and invoked the cancellation handler.
private final class HIDManagerLifetime {
    var manager: IOHIDManager?
    let callbackContext: HIDCallbackContext

    init(manager: IOHIDManager, callbackContext: HIDCallbackContext) {
        self.manager = manager
        self.callbackContext = callbackContext
    }
}

/// Owns all IOHID work on one high-priority serial queue. Input packets are
/// translated immediately, while SwiftUI snapshots are coalesced to 30 Hz.
final class WiimoteHIDController {
    var onSnapshotsChanged: (([ConnectedWiimoteSnapshot]) -> Void)?
    var onConnectionCountChanged: ((Int) -> Void)?
    var logHandler: ((_ icon: String, _ message: String) -> Void)?

    private let queue = DispatchQueue(
        label: "dev.wiimacmote.hid",
        qos: .userInteractive
    )
    private let queueKey = DispatchSpecificKey<Void>()

    private var manager: IOHIDManager?
    private var callbackContext: HIDCallbackContext?
    private var sessions: [UInt64: Session] = [:]
    private var settings: WiimoteHIDSettings
    private var uiTimer: DispatchSourceTimer?
    private var rateTimer: DispatchSourceTimer?
    private var snapshotsDirty = false

    init(settings: WiimoteHIDSettings) {
        self.settings = settings
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            tearDown()
        } else {
            queue.sync { tearDown() }
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.tearDown()
        }
    }

    func updateSettings(_ newSettings: WiimoteHIDSettings) {
        queue.async { [weak self] in
            guard let self else { return }
            let previous = self.settings
            self.settings = newSettings

            for session in self.sessions.values {
                let virtualDeviceConfigurationChanged =
                    previous.virtualGamepadEnabled != newSettings.virtualGamepadEnabled ||
                    previous.virtualGamepadIdentity != newSettings.virtualGamepadIdentity ||
                    previous.virtualGamepadBackendPreference != newSettings.virtualGamepadBackendPreference

                if virtualDeviceConfigurationChanged {
                    if session.virtualGamepad != nil {
                        session.virtualGamepad?.reset()
                        session.virtualGamepad = nil
                    }
                    self.configureVirtualGamepad(for: session)
                }

                if previous.motionRightStickEnabled != newSettings.motionRightStickEnabled ||
                    previous.motionInputSource != newSettings.motionInputSource {
                    session.motionFilter.resetCalibration()
                    self.setReportMode(for: session)
                }

                if previous.diagnosticsDSUEnabled != newSettings.diagnosticsDSUEnabled {
                    self.setReportMode(for: session)
                }

                if previous.motionPlusEnabled != newSettings.motionPlusEnabled {
                    session.motionPlusFilter.resetCalibration()
                    session.motionPlusGyroscope = nil
                    session.motionPlusProbeRequested = false
                    session.motionPlusActivationRequested = false
                    if newSettings.motionPlusEnabled {
                        self.probeOrActivateMotionPlusIfNeeded(for: session)
                    } else {
                        self.deactivateMotionPlusIfNeeded(for: session)
                    }
                    self.setReportMode(for: session)
                }

                if previous.irCameraEnabled != newSettings.irCameraEnabled {
                    if !newSettings.irCameraEnabled {
                        self.disableIR(for: session)
                        session.irPoints = []
                        session.irPointCount = 0
                    }
                    self.setReportMode(for: session)
                }

                self.updateVirtualOutput(for: session)
            }
            self.markSnapshotsDirty()
        }
    }

    func setRumble(id: UInt64, enabled: Bool) {
        queue.async { [weak self] in
            guard let self, let session = self.sessions[id] else { return }
            session.rumbleEnabled = enabled
            self.sendLEDState(for: session)
        }
    }

    func requestStatus(id: UInt64) {
        queue.async { [weak self] in
            guard let self, let session = self.sessions[id] else { return }
            self.sendStatusRequest(for: session)
        }
    }

    func calibrateMotion(id: UInt64) {
        queue.async { [weak self] in
            guard let self, let session = self.sessions[id] else { return }
            session.motionFilter.calibrate(using: self.motionAxes(for: session))
            session.motionPlusFilter.resetCalibration()
            self.log("", "Calibrated motion center for P\(session.playerIndex).")
        }
    }

    func disconnect(id: UInt64) {
        queue.async { [weak self] in
            guard let self, let session = self.sessions[id] else { return }
            self.quietAndClose(session, reason: "P\(session.playerIndex) disconnect requested.")
        }
    }

    // MARK: - Setup

    private func startOnQueue() {
        guard manager == nil else { return }

        let created = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        manager = created

        let vendorID = 0x057E
        let matchOriginal: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: 0x0306
        ]
        let matchTR: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: 0x0330
        ]
        IOHIDManagerSetDeviceMatchingMultiple(
            created,
            [matchOriginal as CFDictionary, matchTR as CFDictionary] as CFArray
        )

        let callbackContext = HIDCallbackContext(owner: self)
        self.callbackContext = callbackContext
        let context = Unmanaged.passUnretained(callbackContext).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(
            created,
            { context, _, _, device in
                guard let context else { return }
                let callbackContext = Unmanaged<HIDCallbackContext>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                callbackContext.owner?.deviceMatched(device)
            },
            context
        )
        IOHIDManagerRegisterDeviceRemovalCallback(
            created,
            { context, _, _, device in
                guard let context else { return }
                let callbackContext = Unmanaged<HIDCallbackContext>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                callbackContext.owner?.deviceRemoved(device)
            },
            context
        )
        IOHIDManagerRegisterInputReportCallback(
            created,
            { context, result, sender, _, reportID, report, reportLength in
                // With a dispatch-backed IOHIDManager, all callbacks must be
                // registered before activation. The manager-level report
                // callback also avoids mutating an already activated device.
                guard let context, let sender else { return }
                let callbackContext = Unmanaged<HIDCallbackContext>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                guard let owner = callbackContext.owner else { return }
                let source = Unmanaged<IOHIDDevice>
                    .fromOpaque(sender)
                    .takeUnretainedValue()
                owner.receivedReport(
                    from: source,
                    result: result,
                    reportID: reportID,
                    report: report,
                    length: reportLength
                )
            },
            context
        )

        let openResult = IOHIDManagerOpen(created, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            log("", "Unable to open IOHIDManager (\(hex(openResult))).")
            callbackContext.owner = nil
            self.callbackContext = nil
            manager = nil
            return
        }

        let lifetime = HIDManagerLifetime(
            manager: created,
            callbackContext: callbackContext
        )
        IOHIDManagerSetDispatchQueue(created, queue)
        IOHIDManagerSetCancelHandler(created) { [lifetime] in
            lifetime.callbackContext.owner = nil
            lifetime.manager = nil
        }
        IOHIDManagerActivate(created)
        startTimers()
        log("", "HID service is ready on its dedicated dispatch queue.")
    }

    private func tearDown() {
        uiTimer?.cancel()
        uiTimer = nil
        rateTimer?.cancel()
        rateTimer = nil

        // Invalidate the old generation before cancellation. Any callback that
        // was already queued will safely no-op, including during stop/start.
        callbackContext?.owner = nil
        callbackContext = nil

        // Input reports and device access are owned by the manager. Avoid any
        // per-device close or callback mutation while a device may be vanishing.
        for session in sessions.values {
            quietRemote(for: session)
            session.virtualGamepad?.reset()
        }
        sessions.removeAll()

        if let manager {
            _ = IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
            IOHIDManagerCancel(manager)
        }
    }

    private func startTimers() {
        let uiTimer = DispatchSource.makeTimerSource(queue: queue)
        uiTimer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(5))
        uiTimer.setEventHandler { [weak self] in
            guard let self, self.snapshotsDirty else { return }
            self.snapshotsDirty = false
            self.publishSnapshots()
        }
        uiTimer.resume()
        self.uiTimer = uiTimer

        let rateTimer = DispatchSource.makeTimerSource(queue: queue)
        rateTimer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        rateTimer.setEventHandler { [weak self] in
            guard let self else { return }
            for session in self.sessions.values {
                session.reportsPerSecond = session.reportCounter
                session.reportCounter = 0
            }
            self.markSnapshotsDirty()
        }
        rateTimer.resume()
        self.rateTimer = rateTimer
    }

    // MARK: - Device lifecycle

    private func deviceMatched(_ device: IOHIDDevice) {
        let id = deviceIdentifier(device)
        guard sessions[id] == nil else { return }
        guard sessions.count < 4 else {
            log("", "Ignoring an additional Wii Remote because four are already active.")
            return
        }

        let name = stringProperty(device, key: kIOHIDProductKey) ?? "Nintendo Wii Remote"
        let playerIndex = firstAvailablePlayerIndex()
        let productID = intProperty(device, key: kIOHIDProductIDKey) ?? 0
        let remoteKind = WiimoteRemoteKind(name: name, productID: productID)
        let session = Session(
            id: id,
            device: device,
            playerIndex: playerIndex,
            name: name,
            address: stringProperty(device, key: kIOHIDSerialNumberKey),
            productID: productID,
            remoteKind: remoteKind
        )
        if remoteKind == .balanceBoard {
            session.extensionKind = .balanceBoard
            session.extensionConnected = true
        }
        sessions[id] = session

        configureVirtualGamepad(for: session)
        if session.extensionKind == .balanceBoard {
            initializeExtension(for: session)
        }
        sendLEDState(for: session)
        setReportMode(for: session)

        // Dolphin similarly allows the new report mode to settle before asking
        // for status; this avoids racing two output transactions at connect.
        queue.asyncAfter(deadline: .now() + .milliseconds(200)) { [weak self, weak session] in
            guard let self, let session, self.sessions[session.id] != nil else { return }
            self.sendStatusRequest(for: session)
            self.probeOrActivateMotionPlusIfNeeded(for: session)
        }

        queue.asyncAfter(deadline: .now() + .milliseconds(350)) { [weak self, weak session] in
            guard let self, let session, self.sessions[session.id] != nil else { return }
            self.sendReadMemory(
                for: session,
                kind: .accelerometerCalibration,
                addressSpace: .eeprom,
                address: WiimoteProtocolCodes.EEPROM.accelerometerCalibration,
                length: 10
            )
        }

        log("", "Connected \(name) as P\(playerIndex).")
        publishConnectionChanges()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let id = deviceIdentifier(device)
        removeSession(id: id, reason: nil)
    }

    private func removeSession(id: UInt64, reason: String?) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.virtualGamepad?.reset()

        // The manager owns report delivery. Its callbacks are serialized on
        // this queue, so no session-owned callback buffer needs a drain period.

        log("", reason ?? "P\(session.playerIndex) disconnected.")
        publishConnectionChanges()
    }

    private func firstAvailablePlayerIndex() -> Int {
        for candidate in 1...4 where !sessions.values.contains(where: { $0.playerIndex == candidate }) {
            return candidate
        }
        return 1
    }

    // MARK: - Reports

    private func receivedReport(
        from device: IOHIDDevice,
        result: IOReturn,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>,
        length: CFIndex
    ) {
        guard result == kIOReturnSuccess else {
            log("", "HID input callback returned \(hex(result)).")
            return
        }
        guard length > 0, let session = sessions[deviceIdentifier(device)] else { return }

        let buffer = UnsafeBufferPointer(start: report, count: length)
        let packet: WiimotePacket?
        if buffer.first == UInt8(truncatingIfNeeded: reportID) || reportID == 0 {
            packet = WiimoteReportParser.parse(buffer)
        } else {
            var normalized = [UInt8(truncatingIfNeeded: reportID)]
            normalized.append(contentsOf: buffer)
            packet = WiimoteReportParser.parse(Data(normalized))
        }

        guard let packet else { return }
        session.reportCounter += 1

        switch packet {
        case .input(let input):
            session.buttons = input.buttons
            session.acceleration = input.acceleration
            session.lastReportID = input.reportID
            session.irPointCount = input.irPoints.count
            session.irPoints = input.irPoints
            if !input.extensionData.isEmpty {
                session.extensionConnected = true
                let decoded = WiimoteExtensionInput.decode(
                    input.extensionData,
                    kind: session.extensionKind
                )
                session.extensionInput = decoded
                if case .motionPlus(let motionPlus)? = decoded {
                    session.motionPlusGyroscope = session.motionPlusFilter.gyroscope(for: motionPlus)
                }
            }
            updateVirtualOutput(for: session)
            markSnapshotsDirty()

        case .status(let status):
            let extensionStateChanged = session.hasReceivedStatus &&
                session.extensionConnected != status.extensionConnected
            session.hasReceivedStatus = true
            session.buttons = status.buttons
            session.batteryPercent = status.batteryPercent
            session.extensionConnected = status.extensionConnected
            session.lastReportID = 0x20
            sendLEDState(for: session)

            // A spontaneous extension connect/disconnect status disables data
            // reporting on the Wii Remote. Restore the selected report mode.
            if extensionStateChanged {
                if status.extensionConnected {
                    initializeExtension(for: session)
                } else {
                    session.extensionKind = nil
                    session.extensionIdentifier = nil
                    session.extensionInput = nil
                    session.motionPlusGyroscope = nil
                    session.motionPlusFilter.resetCalibration()
                    session.balanceBoardCalibration = nil
                    session.extensionInitializationRequested = false
                    session.extensionIdentifierRetryCount = 0
                    session.motionPlusProbeRequested = false
                    session.motionPlusActivationRequested = false
                    session.pendingRead = nil
                }
                setReportMode(for: session)
                log("ℹ", "P\(session.playerIndex) extension state changed; report mode restored.")
            } else if status.extensionConnected,
                      session.extensionKind == nil ||
                      (session.extensionKind == .balanceBoard && session.balanceBoardCalibration == nil) {
                initializeExtension(for: session)
            }
            probeOrActivateMotionPlusIfNeeded(for: session)
            markSnapshotsDirty()

        case .readData(let read):
            handleReadData(read, for: session)
            markSnapshotsDirty()

        case .acknowledgment(let acknowledgedReport, let error):
            if error != 0 {
                log(
                    "",
                    String(format: "P%d rejected output report 0x%02X with error 0x%02X.",
                           session.playerIndex, acknowledgedReport, error)
                )
            }

        case .ignored:
            break
        }
    }

    private func updateVirtualOutput(for session: Session) {
        let motionStick: (x: Int8, y: Int8)?
        if settings.motionRightStickEnabled, let axes = motionAxes(for: session) {
            motionStick = session.motionFilter.stick(
                for: axes,
                profile: settings.profile
            )
        } else {
            motionStick = nil
        }

        let state = GamepadMapper.map(
            buttons: session.buttons,
            extensionInput: session.extensionInput,
            profile: settings.profile,
            motionRightStick: motionStick
        )
        session.gamepadState = state
        guard settings.virtualGamepadEnabled, let gamepad = session.virtualGamepad else { return }
        gamepad.update(state)
    }

    private func motionAxes(for session: Session) -> MotionStickAxes? {
        switch settings.motionInputSource {
        case .automatic:
            return gyroscopeAxes(for: session.motionPlusGyroscope) ?? accelerometerAxes(for: session.acceleration)
        case .accelerometer:
            return accelerometerAxes(for: session.acceleration)
        case .motionPlusGyro:
            return gyroscopeAxes(for: session.motionPlusGyroscope)
        }
    }

    private func accelerometerAxes(for acceleration: WiimoteAcceleration?) -> MotionStickAxes? {
        guard let acceleration else { return nil }
        return MotionStickAxes(x: acceleration.xG, y: acceleration.yG)
    }

    private func gyroscopeAxes(for gyroscope: WiimoteMotionPlusGyroscope?) -> MotionStickAxes? {
        guard let gyroscope else { return nil }
        return MotionStickAxes(
            x: gyroscope.yawDegreesPerSecond / 160.0,
            y: gyroscope.pitchDegreesPerSecond / 160.0
        )
    }

    private func configureVirtualGamepad(for session: Session) {
        if settings.virtualGamepadEnabled {
            guard session.virtualGamepad == nil else { return }
            do {
                let gamepad = try VirtualGamepad(
                    playerIndex: session.playerIndex,
                    identity: settings.virtualGamepadIdentity,
                    backendPreference: settings.virtualGamepadBackendPreference
                )
                session.virtualGamepad = gamepad
                session.virtualGamepadError = nil
                log(
                    "",
                    "P\(session.playerIndex) virtual output: \(gamepad.identity.shortTitle) via \(gamepad.backendKind.rawValue)."
                )
            } catch {
                session.virtualGamepadError = error.localizedDescription
                log("", "Virtual output failed for P\(session.playerIndex): \(error.localizedDescription)")
            }
        } else {
            session.virtualGamepad?.reset()
            session.virtualGamepad = nil
            session.virtualGamepadError = nil
        }
    }

    // MARK: - Output reports

    private func setReportMode(for session: Session) {
        let selection = reportSelection(for: session)
        let delay = applyIRMode(selection.irMode, for: session)
        let report = WiimoteOutputReports.reportMode(
            selection.mode,
            continuous: true,
            rumble: session.rumbleEnabled
        )

        guard delay > 0 else {
            sendOutputReport(report, to: session)
            return
        }

        queue.asyncAfter(deadline: .now() + delay) { [weak self, weak session] in
            guard let self,
                  let session,
                  self.sessions[session.id] === session
            else {
                return
            }
            self.sendOutputReport(report, to: session)
        }
    }

    private func reportSelection(for session: Session) -> (mode: WiimoteReportMode, irMode: WiimoteIRMode?) {
        if session.extensionKind == .balanceBoard {
            return (.buttonsExtension19, nil)
        }

        let hasExtensionData = session.extensionConnected || session.extensionKind != nil
        let wantsRemoteAccelerometerForVirtualStick = settings.motionRightStickEnabled &&
            (settings.motionInputSource != .motionPlusGyro || session.motionPlusGyroscope == nil)
        let wantsRemoteAccelerometer = settings.diagnosticsDSUEnabled || wantsRemoteAccelerometerForVirtualStick

        if settings.irCameraEnabled, hasExtensionData {
            return (.buttonsAccelerometerIR10Extension6, .basic)
        }

        if settings.irCameraEnabled {
            return (.buttonsAccelerometerIR12, .extended)
        }

        if hasExtensionData {
            return (wantsRemoteAccelerometer ? .buttonsAccelerometerExtension16 : .buttonsExtension8, nil)
        }

        return (wantsRemoteAccelerometer ? .buttonsAccelerometer : .buttons, nil)
    }

    private func sendStatusRequest(for session: Session) {
        sendOutputReport(WiimoteOutputReports.statusRequest(rumble: session.rumbleEnabled), to: session)
    }

    private func sendLEDState(for session: Session) {
        let ledMask = UInt8(0x10 << (session.playerIndex - 1))
        sendOutputReport(WiimoteOutputReports.leds(mask: ledMask, rumble: session.rumbleEnabled), to: session)
    }

    private func applyIRMode(_ mode: WiimoteIRMode?, for session: Session) -> TimeInterval {
        guard let mode else {
            if session.irInitializationRequested {
                disableIR(for: session)
            }
            return 0
        }

        guard session.extensionKind != .balanceBoard else { return 0 }
        guard !session.irInitializationRequested || session.irMode != mode else { return 0 }

        session.irInitializationRequested = true
        session.irMode = mode
        sendOutputReports(WiimoteOutputReports.irInitializationSequence(mode: mode), to: session, interval: 0.05)
        log("ℹ", "P\(session.playerIndex) IR camera initialized in \(mode.displayName) mode.")
        return 0.38
    }

    private func disableIR(for session: Session) {
        session.irInitializationRequested = false
        session.irMode = nil
        sendOutputReport(WiimoteOutputReports.irEnabled(false, rumble: session.rumbleEnabled), to: session)
        sendOutputReport(WiimoteOutputReports.irEnabled(false, second: true, rumble: session.rumbleEnabled), to: session)
    }

    private func initializeExtension(for session: Session) {
        guard !session.extensionInitializationRequested else { return }
        session.extensionInitializationRequested = true

        sendOutputReports(WiimoteOutputReports.extensionInitializationSequence(), to: session, interval: 0.05)

        queue.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self, weak session] in
            guard let self, let session, self.sessions[session.id] != nil else { return }
            self.sendReadMemory(
                for: session,
                kind: .extensionIdentifier,
                addressSpace: .register,
                address: WiimoteProtocolCodes.Register.extensionIdentifier,
                length: 6
            )
        }
    }

    private func probeOrActivateMotionPlusIfNeeded(for session: Session) {
        if let kind = session.extensionKind {
            if kind.isMotionPlusInactive {
                if settings.motionPlusEnabled {
                    activateMotionPlus(for: session)
                }
                return
            }
            if kind.isMotionPlusActive {
                return
            }
        }
        guard !session.motionPlusProbeRequested else { return }
        session.motionPlusProbeRequested = true
        sendReadMemory(
            for: session,
            kind: .motionPlusIdentifier,
            addressSpace: .register,
            address: WiimoteProtocolCodes.Register.motionPlusIdentifier,
            length: 6
        )
    }

    private func activateMotionPlus(for session: Session) {
        guard settings.motionPlusEnabled else { return }
        guard !session.motionPlusActivationRequested else { return }
        session.motionPlusActivationRequested = true

        let mode = motionPlusMode(for: session)
        if let initialize = WiimoteOutputReports.motionPlusInitialize() {
            sendOutputReport(initialize, to: session)
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(80)) { [weak self, weak session] in
            guard let self, let session, self.sessions[session.id] === session else { return }
            if let activate = WiimoteOutputReports.motionPlusActivate(mode: mode) {
                self.sendOutputReport(activate, to: session)
                self.log("ℹ", "P\(session.playerIndex) MotionPlus activation requested in \(mode.displayName) mode.")
            }
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(650)) { [weak self, weak session] in
            guard let self, let session, self.sessions[session.id] === session else { return }
            session.extensionInitializationRequested = false
            self.sendReadMemory(
                for: session,
                kind: .extensionIdentifier,
                addressSpace: .register,
                address: WiimoteProtocolCodes.Register.extensionIdentifier,
                length: 6
            )
            self.setReportMode(for: session)
        }
    }

    private func deactivateMotionPlusIfNeeded(for session: Session) {
        guard session.extensionKind?.isMotionPlusActive == true || session.extensionKind?.isMotionPlusInactive == true else {
            return
        }
        if let deactivate = WiimoteOutputReports.motionPlusDeactivate() {
            sendOutputReport(deactivate, to: session)
        }
        session.motionPlusGyroscope = nil
        session.motionPlusFilter.resetCalibration()
        session.motionPlusProbeRequested = false
        session.motionPlusActivationRequested = false
        queue.asyncAfter(deadline: .now() + .milliseconds(600)) { [weak self, weak session] in
            guard let self, let session, self.sessions[session.id] === session else { return }
            session.extensionInitializationRequested = false
            self.sendStatusRequest(for: session)
            self.setReportMode(for: session)
        }
    }

    private func motionPlusMode(for session: Session) -> WiimoteMotionPlusMode {
        switch session.extensionKind {
        case .nunchuk, .motionPlusNunchukPassthrough:
            return .nunchukPassthrough
        case .classicController, .classicControllerPro, .motionPlusClassicPassthrough:
            return .classicPassthrough
        default:
            return .standalone
        }
    }

    private func sendReadMemory(
        for session: Session,
        kind: PendingReadKind,
        addressSpace: WiimoteAddressSpace,
        address: UInt32,
        length: UInt16
    ) {
        guard session.pendingRead == nil else {
            queue.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self, weak session] in
                guard let self, let session, self.sessions[session.id] != nil else { return }
                self.sendReadMemory(
                    for: session,
                    kind: kind,
                    addressSpace: addressSpace,
                    address: address,
                    length: length
                )
            }
            return
        }

        guard let report = WiimoteOutputReports.readMemory(
            addressSpace: addressSpace,
            address: address,
            length: length,
            rumble: session.rumbleEnabled
        ) else { return }

        session.pendingRead = PendingRead(
            kind: kind,
            address: address,
            length: Int(length),
            data: []
        )
        sendOutputReport(report, to: session)
    }

    private func handleReadData(_ read: WiimoteReadData, for session: Session) {
        guard var pending = session.pendingRead else { return }
        if read.error != 0 {
            if pending.kind == .motionPlusIdentifier {
                if session.remoteKind != .motionPlusInside {
                    session.motionPlusCapability = .absent
                }
            } else {
                log(
                    "⚠",
                    String(format: "P%d memory read at 0x%06X failed with error 0x%02X.",
                           session.playerIndex, pending.address, read.error)
                )
            }
            session.pendingRead = nil
            return
        }

        pending.data.append(contentsOf: read.data)
        session.pendingRead = pending
        guard pending.data.count >= pending.length else { return }

        let data = Array(pending.data.prefix(pending.length))
        session.pendingRead = nil

        switch pending.kind {
        case .accelerometerCalibration:
            if let calibration = WiimoteAccelerometerCalibration(bytes: data) {
                session.accelerometerCalibration = calibration
                log(
                    calibration.checksumValid ? "✅" : "⚠",
                    "P\(session.playerIndex) accelerometer EEPROM calibration loaded."
                )
            }

        case .extensionIdentifier:
            let identifier = Array(data.prefix(6))
            if WiimoteExtensionKind.identifierLooksInvalid(identifier), session.extensionIdentifierRetryCount < 3 {
                session.extensionIdentifierRetryCount += 1
                session.extensionInitializationRequested = false
                log("⚠", "P\(session.playerIndex) extension identifier was not stable; retrying handshake.")
                queue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self, weak session] in
                    guard let self, let session, self.sessions[session.id] === session else { return }
                    self.initializeExtension(for: session)
                }
                return
            }

            session.extensionIdentifierRetryCount = 0
            session.extensionIdentifier = identifier
            let kind = WiimoteExtensionKind(identifier: identifier)
            log("🧩", "P\(session.playerIndex) detected \(kind.displayName).")
            if let capability = WiimoteMotionPlusCapability(identifier: identifier, remoteKind: session.remoteKind) {
                session.motionPlusCapability = capability
            }
            if kind.isMotionPlusInactive, !settings.motionPlusEnabled {
                session.extensionConnected = false
                session.extensionKind = nil
                setReportMode(for: session)
                return
            }

            session.extensionKind = kind
            if settings.motionPlusEnabled, kind.isMotionPlusInactive {
                activateMotionPlus(for: session)
            } else if !settings.motionPlusEnabled, kind.isMotionPlusActive {
                deactivateMotionPlusIfNeeded(for: session)
            }
            setReportMode(for: session)
            if kind == .balanceBoard {
                sendReadMemory(
                    for: session,
                    kind: .balanceBoardCalibration,
                    addressSpace: .register,
                    address: WiimoteProtocolCodes.Register.extensionCalibration,
                    length: 32
                )
            }

        case .motionPlusIdentifier:
            let identifier = Array(data.prefix(6))
            let kind = WiimoteExtensionKind(identifier: identifier)
            if let capability = WiimoteMotionPlusCapability(identifier: identifier, remoteKind: session.remoteKind) {
                session.motionPlusCapability = capability
            }
            if kind.isMotionPlus {
                session.extensionIdentifier = identifier
                log("🧩", "P\(session.playerIndex) detected \(kind.displayName).")
                if settings.motionPlusEnabled {
                    session.extensionConnected = true
                    session.extensionKind = kind
                }
                if settings.motionPlusEnabled, kind.isMotionPlusInactive {
                    activateMotionPlus(for: session)
                } else if !settings.motionPlusEnabled, kind.isMotionPlusActive {
                    session.extensionConnected = true
                    session.extensionKind = kind
                    deactivateMotionPlusIfNeeded(for: session)
                }
                setReportMode(for: session)
            }

        case .balanceBoardCalibration:
            if let calibration = WiimoteBalanceBoardCalibration(bytes: data) {
                session.balanceBoardCalibration = calibration
                log("✅", "P\(session.playerIndex) Balance Board calibration loaded.")
            }
        }
    }

    private func quietAndClose(_ session: Session, reason: String) {
        quietRemote(for: session)
        session.virtualGamepad?.reset()

        queue.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self, weak session] in
            guard let self, let session, self.sessions[session.id] != nil else { return }
            let result = IOHIDDeviceClose(session.device, IOOptionBits(kIOHIDOptionsTypeNone))
            if result != kIOReturnSuccess {
                self.log("⚠", "P\(session.playerIndex) HID close returned \(self.hex(result)).")
            }
            self.removeSession(id: session.id, reason: reason)
        }
    }

    private func quietRemote(for session: Session) {
        session.rumbleEnabled = false

        // There is no public Wii Remote power-off report. The closest safe
        // shutdown sequence is to stop speaker/IR output, blank LEDs, and force
        // rumble off before closing the Bluetooth HID connection.
        sendOutputReport(to: session, reportID: WiimoteProtocolCodes.OutputReport.speakerMute, payload: [WiimoteProtocolCodes.OutputFlag.enable])
        sendOutputReport(to: session, reportID: WiimoteProtocolCodes.OutputReport.speakerEnable, payload: [0x00])
        sendOutputReport(to: session, reportID: WiimoteProtocolCodes.OutputReport.irEnable, payload: [0x00])
        sendOutputReport(to: session, reportID: WiimoteProtocolCodes.OutputReport.irEnable2, payload: [0x00])
        sendOutputReport(to: session, reportID: WiimoteProtocolCodes.OutputReport.leds, payload: [0x00])
        sendOutputReport(to: session, reportID: WiimoteProtocolCodes.OutputReport.rumble, payload: [0x00])
    }

    private func sendOutputReport(_ report: WiimoteOutputReport, to session: Session) {
        sendOutputReport(to: session, reportID: report.reportID, payload: report.payload)
    }

    private func sendOutputReports(
        _ reports: [WiimoteOutputReport],
        to session: Session,
        interval: TimeInterval
    ) {
        for (index, report) in reports.enumerated() {
            queue.asyncAfter(deadline: .now() + interval * Double(index)) { [weak self, weak session] in
                guard let self,
                      let session,
                      self.sessions[session.id] === session
                else {
                    return
                }
                self.sendOutputReport(report, to: session)
            }
        }
    }

    private func sendOutputReport(
        to session: Session,
        reportID: UInt8,
        payload: [UInt8]
    ) {
        // IOHID uses the report ID as a separate argument, but Bluetooth HID
        // still expects that same ID as the first byte in the report buffer.
        var bytes = [reportID]
        bytes.append(contentsOf: payload)

        let result = bytes.withUnsafeBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.baseAddress else {
                return kIOReturnBadArgument
            }
            return IOHIDDeviceSetReport(
                session.device,
                kIOHIDReportTypeOutput,
                CFIndex(reportID),
                baseAddress.assumingMemoryBound(to: UInt8.self),
                bytes.count
            )
        }

        if result != kIOReturnSuccess {
            log(
                "",
                String(format: "P%d output report 0x%02X failed (%@).",
                       session.playerIndex, reportID, hex(result))
            )
        }
    }

    // MARK: - Snapshot publication

    private func markSnapshotsDirty() {
        snapshotsDirty = true
    }

    private func publishConnectionChanges() {
        markSnapshotsDirty()
        let count = sessions.count
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionCountChanged?(count)
        }
    }

    private func publishSnapshots() {
        let snapshots = sessions.values
            .sorted { $0.playerIndex < $1.playerIndex }
            .map { session in
                ConnectedWiimoteSnapshot(
                    id: session.id,
                    playerIndex: session.playerIndex,
                    name: session.name,
                    address: session.address,
                    productID: session.productID,
                    remoteKind: session.remoteKind,
                    motionPlusCapability: session.motionPlusCapability,
                    batteryPercent: session.batteryPercent,
                    buttons: session.buttons.labels,
                    gamepadState: session.gamepadState,
                    acceleration: session.acceleration,
                    extensionAcceleration: extensionAcceleration(for: session.extensionInput),
                    motionPlusGyroscope: session.motionPlusGyroscope,
                    reportsPerSecond: session.reportsPerSecond,
                    reportID: session.lastReportID,
                    extensionConnected: session.extensionConnected,
                    extensionName: session.extensionKind?.displayName,
                    extensionDetail: session.extensionDetail,
                    extensionIdentifier: session.extensionIdentifier,
                    extensionIdentifierHex: session.extensionIdentifier.map(WiimoteIdentifierFormatter.hexString),
                    extensionInputSignature: extensionInputSignature(for: session.extensionInput),
                    irPointCount: session.irPointCount,
                    irPoints: session.irPoints,
                    balanceWeightKilograms: session.balanceWeightKilograms,
                    virtualGamepadActive: session.virtualGamepad != nil,
                    virtualGamepadIdentity: session.virtualGamepad?.identity.shortTitle,
                    virtualGamepadBackend: session.virtualGamepad?.backendKind.rawValue,
                    virtualGamepadError: session.virtualGamepadError
                )
            }

        DispatchQueue.main.async { [weak self] in
            self?.onSnapshotsChanged?(snapshots)
        }
    }

    private func extensionAcceleration(for input: WiimoteExtensionInput?) -> WiimoteAcceleration? {
        switch input {
        case .nunchuk(let nunchuk):
            return nunchuk.acceleration
        default:
            return nil
        }
    }

    private func extensionInputSignature(for input: WiimoteExtensionInput?) -> String? {
        switch input {
        case .nunchuk(let nunchuk):
            return "nunchuk:\(Int(nunchuk.stickX) / 4),\(Int(nunchuk.stickY) / 4),\(nunchuk.cPressed),\(nunchuk.zPressed)"
        case .classicController(let classic):
            return "classic:\(classic.leftX / 2),\(classic.leftY / 2),\(classic.rightX / 2),\(classic.rightY / 2),\(classic.leftTrigger / 2),\(classic.rightTrigger / 2),\(classic.buttons.rawValue)"
        case .guitar(let guitar):
            return "guitar:\(Int(guitar.stickX) / 4),\(Int(guitar.stickY) / 4),\(guitar.whammyPercent / 5),\(guitar.buttons.rawValue)"
        case .balanceBoard(let board):
            return "balance:\(board.sensors.topRight / 8),\(board.sensors.bottomRight / 8),\(board.sensors.topLeft / 8),\(board.sensors.bottomLeft / 8)"
        case .tatacon(let tatacon):
            return "tatacon:\(tatacon.buttons.rawValue)"
        case .raw(let kind, let bytes):
            return "raw:\(kind.displayName):\(bytes.prefix(8).map { String($0) }.joined(separator: ","))"
        case .motionPlus, .none:
            return nil
        }
    }

    // MARK: - Helpers

    private func log(_ icon: String, _ message: String) {
        logHandler?(icon, message)
    }

    private func deviceIdentifier(_ device: IOHIDDevice) -> UInt64 {
        UInt64(CFHash(device))
    }

    private func property(_ device: IOHIDDevice, key: String) -> CFTypeRef? {
        let cfKey = key.withCString { pointer in
            CFStringCreateWithCString(
                kCFAllocatorDefault,
                pointer,
                CFStringBuiltInEncodings.UTF8.rawValue
            )
        }
        guard let cfKey else { return nil }
        return IOHIDDeviceGetProperty(device, cfKey)
    }

    private func stringProperty(_ device: IOHIDDevice, key: String) -> String? {
        property(device, key: key) as? String
    }

    private func intProperty(_ device: IOHIDDevice, key: String) -> Int? {
        (property(device, key: key) as? NSNumber)?.intValue
    }

    private func hex(_ value: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: value))
    }
}

private enum PendingReadKind: Equatable {
    case accelerometerCalibration
    case extensionIdentifier
    case motionPlusIdentifier
    case balanceBoardCalibration
}

private struct PendingRead {
    let kind: PendingReadKind
    let address: UInt32
    let length: Int
    var data: [UInt8]
}

private final class Session {
    let id: UInt64
    let device: IOHIDDevice
    let playerIndex: Int
    let name: String
    let address: String?
    let productID: Int
    let remoteKind: WiimoteRemoteKind
    let motionFilter = MotionStickFilter()
    let motionPlusFilter = MotionPlusRateFilter()

    var virtualGamepad: VirtualGamepad?
    var virtualGamepadError: String?
    var batteryPercent: Int?
    var buttons: WiimoteButtons = []
    var gamepadState = VirtualGamepadState.neutral
    var acceleration: WiimoteAcceleration?
    var reportsPerSecond = 0
    var reportCounter = 0
    var lastReportID: UInt8?
    var hasReceivedStatus = false
    var extensionConnected = false
    var extensionKind: WiimoteExtensionKind?
    var extensionIdentifier: [UInt8]?
    var extensionInput: WiimoteExtensionInput?
    var extensionInitializationRequested = false
    var extensionIdentifierRetryCount = 0
    var motionPlusCapability: WiimoteMotionPlusCapability
    var motionPlusProbeRequested = false
    var motionPlusActivationRequested = false
    var motionPlusGyroscope: WiimoteMotionPlusGyroscope?
    var accelerometerCalibration: WiimoteAccelerometerCalibration?
    var balanceBoardCalibration: WiimoteBalanceBoardCalibration?
    var pendingRead: PendingRead?
    var irPointCount = 0
    var irPoints: [WiimoteIRPoint] = []
    var irInitializationRequested = false
    var irMode: WiimoteIRMode?
    var rumbleEnabled = false

    var extensionDetail: String? {
        extensionInput?.summary
    }

    var balanceWeightKilograms: Double? {
        guard case .balanceBoard(let input) = extensionInput,
              let calibration = balanceBoardCalibration
        else {
            return nil
        }
        return calibration.weight(for: input).totalKilograms
    }

    init(
        id: UInt64,
        device: IOHIDDevice,
        playerIndex: Int,
        name: String,
        address: String?,
        productID: Int,
        remoteKind: WiimoteRemoteKind
    ) {
        self.id = id
        self.device = device
        self.playerIndex = playerIndex
        self.name = name
        self.address = address
        self.productID = productID
        self.remoteKind = remoteKind
        self.motionPlusCapability = WiimoteMotionPlusCapability(remoteKind: remoteKind)
    }
}

private struct MotionStickAxes {
    let x: Double
    let y: Double
}

private final class MotionStickFilter {
    private var baselineX: Double?
    private var baselineY: Double?
    private var filteredX: Double?
    private var filteredY: Double?

    func resetCalibration() {
        baselineX = nil
        baselineY = nil
        filteredX = nil
        filteredY = nil
    }

    func calibrate(using axes: MotionStickAxes?) {
        guard let axes else {
            resetCalibration()
            return
        }
        baselineX = axes.x
        baselineY = axes.y
        filteredX = axes.x
        filteredY = axes.y
    }

    func stick(
        for axes: MotionStickAxes,
        profile: ControllerProfile
    ) -> (x: Int8, y: Int8) {
        if baselineX == nil || baselineY == nil {
            calibrate(using: axes)
        }

        let alpha = 0.18
        filteredX = lowPass(previous: filteredX, next: axes.x, alpha: alpha)
        filteredY = lowPass(previous: filteredY, next: axes.y, alpha: alpha)

        let xDelta = (filteredX ?? axes.x) - (baselineX ?? axes.x)
        let yDelta = (filteredY ?? axes.y) - (baselineY ?? axes.y)

        let oriented: (Double, Double)
        switch profile {
        case .upright:
            oriented = (xDelta, yDelta)
        case .sideways:
            oriented = (yDelta, -xDelta)
        }

        return (
            axisValue(oriented.0),
            axisValue(oriented.1)
        )
    }

    private func lowPass(previous: Double?, next: Double, alpha: Double) -> Double {
        guard let previous else { return next }
        return previous + alpha * (next - previous)
    }

    private func axisValue(_ value: Double) -> Int8 {
        let deadZone = 0.08
        guard abs(value) > deadZone else { return 0 }
        let adjusted = value - (value.sign == .minus ? -deadZone : deadZone)
        let scaled = Int((adjusted * 150.0).rounded())
        return Int8(clamping: min(max(scaled, -127), 127))
    }
}

private final class MotionPlusRateFilter {
    private var baselineYaw: UInt16?
    private var baselineRoll: UInt16?
    private var baselinePitch: UInt16?

    func resetCalibration() {
        baselineYaw = nil
        baselineRoll = nil
        baselinePitch = nil
    }

    func gyroscope(for input: WiimoteMotionPlusInput) -> WiimoteMotionPlusGyroscope {
        if baselineYaw == nil || baselineRoll == nil || baselinePitch == nil {
            calibrate(using: input)
        }

        return WiimoteMotionPlusGyroscope(
            rawYaw: input.yaw,
            rawRoll: input.roll,
            rawPitch: input.pitch,
            yawDegreesPerSecond: rate(raw: input.yaw, baseline: baselineYaw, slowMode: input.yawSlowMode),
            rollDegreesPerSecond: rate(raw: input.roll, baseline: baselineRoll, slowMode: input.rollSlowMode),
            pitchDegreesPerSecond: rate(raw: input.pitch, baseline: baselinePitch, slowMode: input.pitchSlowMode),
            yawSlowMode: input.yawSlowMode,
            rollSlowMode: input.rollSlowMode,
            pitchSlowMode: input.pitchSlowMode
        )
    }

    private func calibrate(using input: WiimoteMotionPlusInput) {
        baselineYaw = input.yaw
        baselineRoll = input.roll
        baselinePitch = input.pitch
    }

    private func rate(raw: UInt16, baseline: UInt16?, slowMode: Bool) -> Double {
        guard let baseline else { return 0 }
        let delta = Double(Int(raw) - Int(baseline))
        let degreesPerSecond = delta / (slowMode ? 20.0 : 4.0)
        return abs(degreesPerSecond) < 0.5 ? 0 : degreesPerSecond
    }
}
