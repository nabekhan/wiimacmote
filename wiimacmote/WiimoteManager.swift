import AppKit
import Combine
import CoreBluetooth
import Foundation
import IOBluetooth
import Security

final class DiagnosticLog: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let time: Date
        let level: String
        let symbolName: String
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    func append(_ icon: String, _ message: String) {
        let presentation = Self.presentation(for: icon)
        let work = { [weak self] in
            guard let self else { return }
            self.entries.append(Entry(
                time: Date(),
                level: presentation.level,
                symbolName: presentation.symbolName,
                message: message
            ))
            if self.entries.count > 500 {
                self.entries.removeFirst(self.entries.count - 500)
            }
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
        print("[\(presentation.level)] \(message)")
    }

    func clear() {
        if Thread.isMainThread {
            entries.removeAll()
        } else {
            DispatchQueue.main.async { [weak self] in self?.entries.removeAll() }
        }
    }

    var plainText: String {
        let formatter = ISO8601DateFormatter()
        return entries
            .map { "\(formatter.string(from: $0.time)) [\($0.level)] \($0.message)" }
            .joined(separator: "\n")
    }

    private static func presentation(for marker: String) -> (level: String, symbolName: String) {
        switch marker {
        case "❌": return ("Error", "xmark.circle.fill")
        case "⚠️", "⚠": return ("Warning", "exclamationmark.triangle.fill")
        case "✅": return ("Success", "checkmark.circle.fill")
        case "🔍", "👀": return ("Discovery", "dot.radiowaves.left.and.right")
        case "🔐", "🔑": return ("Pairing", "link.circle.fill")
        case "🗑": return ("Removal", "trash.circle.fill")
        case "🔏": return ("Signing", "signature")
        case "🚀": return ("App", "app.badge")
        case "🧩": return ("Extension", "puzzlepiece.extension.fill")
        case "ℹ️", "ℹ": return ("Info", "info.circle.fill")
        default: return ("Info", "circle.fill")
        }
    }
}

enum WiimoteAppPhase: Equatable {
    case starting
    case idle
    case scanning
    case pairing(name: String, attempt: Int)
    case waitingForHID(name: String)
    case connected(count: Int)
    case bluetoothOff
    case permissionDenied
    case error(String)

    var title: String {
        switch self {
        case .starting: return "Starting Bluetooth services…"
        case .idle: return "Ready"
        case .scanning: return "Scanning for a Wii Remote…"
        case .pairing(let name, let attempt): return "Pairing \(name) · attempt \(attempt)"
        case .waitingForHID(let name): return "Waiting for \(name) to expose HID… Connection can take a moment."
        case .connected(let count): return "\(count) Wii Remote\(count == 1 ? "" : "s") connected"
        case .bluetoothOff: return "Bluetooth is turned off"
        case .permissionDenied: return "Bluetooth permission is denied"
        case .error(let message): return message
        }
    }

    var isBusy: Bool {
        switch self {
        case .starting, .scanning, .pairing, .waitingForHID: return true
        default: return false
        }
    }
}

struct SavedWiimoteSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let isConnected: Bool
    let remoteKind: WiimoteRemoteKind
    let motionPlusCapability: WiimoteMotionPlusCapability
    let extensions: [SavedExtensionSnapshot]
}

struct SavedExtensionSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let identifierHex: String
    let lastSeen: Date
}

final class WiimoteManager: NSObject, ObservableObject {
    @Published private(set) var phase: WiimoteAppPhase = .starting
    @Published private(set) var isScanning = false
    @Published private(set) var wiimotes: [ConnectedWiimoteSnapshot] = []
    @Published private(set) var savedWiimotes: [SavedWiimoteSnapshot] = []

    @Published var automaticScanning: Bool {
        didSet {
            defaults.set(automaticScanning, forKey: Keys.automaticScanning)
            if automaticScanning {
                startScanning()
            } else {
                stopScanning()
            }
        }
    }

    @Published var virtualGamepadEnabled: Bool {
        didSet {
            defaults.set(virtualGamepadEnabled, forKey: Keys.virtualGamepadEnabled)
            applyHIDSettings()
        }
    }

    @Published var virtualGamepadIdentity: VirtualGamepadIdentity {
        didSet {
            defaults.set(virtualGamepadIdentity.rawValue, forKey: Keys.virtualGamepadIdentity)
            applyHIDSettings()
        }
    }

    @Published var virtualGamepadBackendPreference: VirtualGamepadBackendPreference {
        didSet {
            defaults.set(
                virtualGamepadBackendPreference.rawValue,
                forKey: Keys.virtualGamepadBackendPreference
            )
            applyHIDSettings()
        }
    }

    @Published var controllerProfile: ControllerProfile {
        didSet {
            defaults.set(controllerProfile.rawValue, forKey: Keys.controllerProfile)
            applyHIDSettings()
        }
    }

    @Published var motionRightStickEnabled: Bool {
        didSet {
            defaults.set(motionRightStickEnabled, forKey: Keys.motionRightStickEnabled)
            applyHIDSettings()
        }
    }

    @Published var motionInputSource: MotionInputSource {
        didSet {
            defaults.set(motionInputSource.rawValue, forKey: Keys.motionInputSource)
            applyHIDSettings()
        }
    }

    @Published var motionPlusEnabled: Bool {
        didSet {
            defaults.set(motionPlusEnabled, forKey: Keys.motionPlusEnabled)
            applyHIDSettings()
        }
    }

    @Published var irCameraEnabled: Bool {
        didSet {
            defaults.set(irCameraEnabled, forKey: Keys.irCameraEnabled)
            applyHIDSettings()
        }
    }

    @Published var diagnosticsDSUEnabled: Bool {
        didSet {
            defaults.set(diagnosticsDSUEnabled, forKey: Keys.diagnosticsDSUEnabled)
            applyHIDSettings()
            configureDiagnosticDSU()
        }
    }

    @Published private(set) var diagnosticsDSUClientCount = 0
    @Published private(set) var diagnosticsDSUError: String?
    @Published private(set) var diagnosticsDSURunning = false

    let diagnostics = DiagnosticLog()

    private enum Keys {
        static let automaticScanning = "automaticScanning"
        static let virtualGamepadEnabled = "virtualGamepadEnabled"
        static let virtualGamepadIdentity = "virtualGamepadIdentity"
        static let virtualGamepadBackendPreference = "virtualGamepadBackendPreference"
        static let controllerProfile = "controllerProfile"
        static let motionRightStickEnabled = "motionRightStickEnabled"
        static let motionInputSource = "motionInputSource"
        static let motionPlusEnabled = "motionPlusEnabled"
        static let irCameraEnabled = "irCameraEnabled"
        static let diagnosticsDSUEnabled = "diagnosticsDSUEnabled"
        static let savedControllerRecords = "savedControllerRecords"
    }

    private struct SavedControllerRecord: Codable, Equatable {
        var remoteKind: WiimoteRemoteKind = .unknown
        var motionPlusCapability: WiimoteMotionPlusCapability = .unknown
        var extensions: [SavedExtensionRecord] = []
    }

    private struct SavedExtensionRecord: Codable, Equatable {
        var identifierHex: String
        var name: String
        var lastSeen: Date
    }

    private let defaults: UserDefaults
    private lazy var hidController = WiimoteHIDController(settings: currentHIDSettings)
    private var centralManager: CBCentralManager?
    private var inquiry: IOBluetoothDeviceInquiry?
    private var pairingBridge: WMPairingBridge?
    private var activePairingToken: UUID?
    private var pairingAttempts: [String: Int] = [:]
    private var pairingCooldowns: [String: Date] = [:]
    private var connectionCooldowns: [String: Date] = [:]
    private var retryWorkItem: DispatchWorkItem?
    private var hidWaitWorkItem: DispatchWorkItem?
    private var hidWaitRecoveryWorkItem: DispatchWorkItem?
    private var inquiryStopReason: String?
    private var suppressInquiryCompletionUntil: Date?
    private var hasStarted = false
    private var savedControllerRecords: [String: SavedControllerRecord] = [:]
    private let diagnosticsDSUPort: UInt16 = 26760
    private lazy var diagnosticDSUServer = DiagnosticDSUServer(port: diagnosticsDSUPort)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.automaticScanning = defaults.object(forKey: Keys.automaticScanning) as? Bool ?? true
        self.virtualGamepadEnabled = defaults.object(forKey: Keys.virtualGamepadEnabled) as? Bool ?? false
        let defaultVirtualIdentity: VirtualGamepadIdentity = .generic
        self.virtualGamepadIdentity = VirtualGamepadIdentity(
            rawValue: defaults.string(forKey: Keys.virtualGamepadIdentity) ?? ""
        ) ?? defaultVirtualIdentity
        let defaultVirtualBackend: VirtualGamepadBackendPreference = .automatic
        self.virtualGamepadBackendPreference = VirtualGamepadBackendPreference(
            rawValue: defaults.string(forKey: Keys.virtualGamepadBackendPreference) ?? ""
        ) ?? defaultVirtualBackend
        self.motionRightStickEnabled = defaults.object(forKey: Keys.motionRightStickEnabled) as? Bool ?? false
        self.motionInputSource = MotionInputSource(
            rawValue: defaults.string(forKey: Keys.motionInputSource) ?? ""
        ) ?? .automatic
        self.motionPlusEnabled = defaults.object(forKey: Keys.motionPlusEnabled) as? Bool ?? false
        self.irCameraEnabled = defaults.object(forKey: Keys.irCameraEnabled) as? Bool ?? false
        self.diagnosticsDSUEnabled = defaults.object(forKey: Keys.diagnosticsDSUEnabled) as? Bool ?? false
        self.controllerProfile = ControllerProfile(
            rawValue: defaults.string(forKey: Keys.controllerProfile) ?? ""
        ) ?? .sideways
        super.init()
        self.savedControllerRecords = loadSavedControllerRecords()
        configureHIDCallbacks()
    }

    deinit {
        cancelPairingWork()
        stopInquiry(reason: "manager teardown")
        centralManager?.delegate = nil
        hidController.stop()
        diagnosticDSUServer.stop()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        hidController.start()
        configureDiagnosticDSUCallbacks()
        refreshSavedWiimotes()
        diagnostics.append(
            "🚀",
            "WiiMacMote 2.0.5 (\(WiiMacMoteBuildFlavor.title)) initialized."
        )
        diagnostics.append("ℹ️", bluetoothRuntimeSummary())

        let environment = DeveloperLabEnvironment.snapshot()
        diagnostics.append(
            environment.virtualHIDEntitlementVisible ? "✅" : "ℹ️",
            environment.entitlementSummary
        )
        diagnostics.append("🔏", environment.signingSummary)
        diagnostics.append(
            environment.amfiRelaxationHintDetected ? "⚠️" : "ℹ️",
            environment.amfiSummary
        )

        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
        configureDiagnosticDSU()
    }

    func startScanning() {
        guard hasStarted else {
            start()
            return
        }
        guard let state = centralManager?.state else {
            diagnostics.append("ℹ️", "Bluetooth permission probe has not started yet.")
            return
        }
        guard state == .poweredOn else {
            diagnostics.append("ℹ️", "Scan requested while CoreBluetooth state is \(bluetoothStateName(state)).")
            if automaticScanning {
                resumeScanning(after: 1)
            }
            return
        }
        guard pairingBridge == nil, activePairingToken == nil else { return }
        guard retryWorkItem == nil, hidWaitWorkItem == nil, hidWaitRecoveryWorkItem == nil else { return }
        guard wiimotes.count < 4 else { return }
        guard !isScanning else { return }

        let inquiry: IOBluetoothDeviceInquiry
        if let existing = self.inquiry {
            inquiry = existing
        } else {
            inquiry = IOBluetoothDeviceInquiry(delegate: self)
            inquiry.searchType = kIOBluetoothDeviceSearchClassic.rawValue
            inquiry.updateNewDeviceNames = true
            self.inquiry = inquiry
        }

        inquiryStopReason = nil
        if let deadline = suppressInquiryCompletionUntil, deadline <= Date() {
            suppressInquiryCompletionUntil = nil
        }
        inquiry.clearFoundDevices()
        let result = inquiry.start()
        guard result == kIOReturnSuccess else {
            phase = .error("Bluetooth scan could not start (\(hex(result))).")
            diagnostics.append("❌", "Classic Bluetooth inquiry failed to start: \(hex(result)).")
            diagnostics.append("ℹ️", bluetoothRuntimeSummary(inquiryResult: result))
            resetInquiryIfNeeded(inquiry)
            if automaticScanning {
                resumeScanning(after: 0.75)
            }
            return
        }

        isScanning = true
        if wiimotes.isEmpty {
            phase = .scanning
        }
        diagnostics.append("🔍", "Classic Bluetooth inquiry started. New controllers: press red SYNC. Saved Wii Remotes: press a face button; press it again if LEDs stop blinking.")
    }

    func stopScanning() {
        stopInquiry(reason: "manual stop")
        isScanning = false
        if wiimotes.isEmpty {
            phase = .idle
        }
    }

    func disconnectWiimote(id: UInt64) {
        if let address = wiimotes.first(where: { $0.id == id })?.address {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.disconnectSavedWiimote(address: address)
            }
        }
        hidController.disconnect(id: id)
    }

    func disconnectSavedWiimote(address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            diagnostics.append("", "Saved remote \(address) is no longer available to Bluetooth.")
            refreshSavedWiimotes()
            return
        }

        if device.isConnected() {
            let result = device.closeConnection()
            if result != kIOReturnSuccess {
                diagnostics.append("", "Disconnect returned \(hex(result)) for \(address).")
            } else {
                diagnostics.append("", "Disconnect requested for \(device.name ?? address).")
            }
        }
        refreshSavedWiimotes()
    }

    func removeSavedWiimote(address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            diagnostics.append("⚠️", "Saved remote \(address) is no longer available to Bluetooth.")
            refreshSavedWiimotes()
            return
        }

        let name = device.name ?? address
        stopInquiry(reason: "removing saved remote")
        cancelPairingWork()
        if device.isConnected() {
            let closeResult = device.closeConnection()
            if closeResult != kIOReturnSuccess {
                diagnostics.append("⚠️", "Disconnect before removal returned \(hex(closeResult)) for \(name).")
            }
        }

        diagnostics.append("🗑", "Removing \(name) from macOS Bluetooth saved devices.")
        WMDeviceRemovalBridge.removePairing(for: device) { [weak self] result, detail in
            guard let self else { return }
            if result == kIOReturnSuccess {
                self.connectionCooldowns[address] = nil
                self.pairingCooldowns[address] = nil
                self.pairingAttempts[address] = nil
                self.savedControllerRecords[self.normalizedBluetoothAddress(address)] = nil
                self.saveSavedControllerRecords()
                let method = detail?.isEmpty == false ? " via \(detail!)" : ""
                self.diagnostics.append("✅", "Removed \(name) from macOS Bluetooth saved devices\(method).")
            } else {
                let explanation = detail?.isEmpty == false ? detail! : self.machErrorDescription(result)
                self.diagnostics.append(
                    "❌",
                    "Could not remove \(name) from macOS Bluetooth saved devices: \(self.hex(result)) \(explanation)"
                )
            }
            self.refreshSavedWiimotes()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                self?.refreshSavedWiimotes()
            }
        }
    }

    func retryNow() {
        cancelPairingWork()
        pairingCooldowns.removeAll()
        connectionCooldowns.removeAll()
        pairingAttempts.removeAll()
        startScanning()
    }

    func setRumble(id: UInt64, enabled: Bool) {
        hidController.setRumble(id: id, enabled: enabled)
    }

    func requestStatus(id: UInt64) {
        hidController.requestStatus(id: id)
    }

    func calibrateMotion(id: UInt64) {
        hidController.calibrateMotion(id: id)
    }

    var diagnosticsDSUStatusText: String {
        let endpoint = "udp://127.0.0.1:\(diagnosticsDSUPort)"
        guard diagnosticsDSUEnabled else { return "Off - \(endpoint)" }
        if let diagnosticsDSUError {
            return "Error - \(diagnosticsDSUError)"
        }
        guard diagnosticsDSURunning else { return "Starting - \(endpoint)" }
        return "\(endpoint) - \(diagnosticsDSUClientCount) client\(diagnosticsDSUClientCount == 1 ? "" : "s")"
    }

    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }

    func openBluetoothPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private var currentHIDSettings: WiimoteHIDSettings {
        WiimoteHIDSettings(
            virtualGamepadEnabled: virtualGamepadEnabled,
            virtualGamepadIdentity: virtualGamepadIdentity,
            virtualGamepadBackendPreference: virtualGamepadBackendPreference,
            profile: controllerProfile,
            motionRightStickEnabled: motionRightStickEnabled,
            motionInputSource: motionInputSource,
            motionPlusEnabled: motionPlusEnabled,
            irCameraEnabled: irCameraEnabled,
            diagnosticsDSUEnabled: diagnosticsDSUEnabled
        )
    }

    private func applyHIDSettings() {
        guard hasStarted else { return }
        hidController.updateSettings(currentHIDSettings)
    }

    private func configureHIDCallbacks() {
        hidController.logHandler = { [weak self] icon, message in
            self?.diagnostics.append(icon, message)
        }
        hidController.onSnapshotsChanged = { [weak self] snapshots in
            self?.wiimotes = snapshots
            self?.persistObservedControllerRecords(from: snapshots)
            self?.refreshSavedWiimotes()
            self?.publishDiagnosticDSUSnapshots(snapshots)
        }
        hidController.onConnectionCountChanged = { [weak self] count in
            self?.handleConnectionCountChanged(count)
        }
    }

    private func configureDiagnosticDSUCallbacks() {
        diagnosticDSUServer.onRumble = { [weak self] command in
            self?.handleDiagnosticDSURumble(command)
        }
        diagnosticDSUServer.onStateChanged = { [weak self] isRunning, clientCount, error in
            guard let self else { return }
            let wasRunning = self.diagnosticsDSURunning
            let previousError = self.diagnosticsDSUError
            self.diagnosticsDSUClientCount = clientCount
            self.diagnosticsDSUError = error
            self.diagnosticsDSURunning = isRunning
            if let error, error != previousError {
                self.diagnostics.append("⚠", "Diagnostics DSU server failed: \(error)")
            } else if isRunning && !wasRunning {
                self.diagnostics.append(
                    "ℹ",
                    "Diagnostics DSU server listening on udp://127.0.0.1:\(self.diagnosticsDSUPort)."
                )
            }
        }
    }

    private func configureDiagnosticDSU() {
        guard hasStarted else { return }
        if diagnosticsDSUEnabled {
            diagnosticDSUServer.start()
            publishDiagnosticDSUSnapshots(wiimotes)
        } else {
            diagnosticDSUServer.updateControllers([])
            diagnosticDSUServer.stop()
            diagnosticsDSUClientCount = 0
            diagnosticsDSUError = nil
            diagnosticsDSURunning = false
        }
    }

    private func publishDiagnosticDSUSnapshots(_ snapshots: [ConnectedWiimoteSnapshot]) {
        guard diagnosticsDSUEnabled else { return }
        diagnosticDSUServer.updateControllers(snapshots.map(controllerRuntimeSnapshot))
    }

    private func controllerRuntimeSnapshot(_ wiimote: ConnectedWiimoteSnapshot) -> ControllerRuntimeSnapshot {
        let slot = min(max(wiimote.playerIndex - 1, 0), 3)
        return ControllerRuntimeSnapshot(
            id: wiimote.id,
            slot: slot,
            name: wiimote.name,
            address: wiimote.address,
            batteryPercent: wiimote.batteryPercent,
            transport: .bluetooth,
            gamepadState: wiimote.gamepadState,
            motion: ControllerMotionState(
                accelerationXG: wiimote.acceleration?.xG ?? 0,
                accelerationYG: wiimote.acceleration?.yG ?? 0,
                accelerationZG: wiimote.acceleration?.zG ?? 0,
                gyroPitchDegreesPerSecond: wiimote.motionPlusGyroscope?.pitchDegreesPerSecond ?? 0,
                gyroYawDegreesPerSecond: wiimote.motionPlusGyroscope?.yawDegreesPerSecond ?? 0,
                gyroRollDegreesPerSecond: wiimote.motionPlusGyroscope?.rollDegreesPerSecond ?? 0
            ),
            hasFullGyro: wiimote.motionPlusGyroscope != nil
        )
    }

    private func handleDiagnosticDSURumble(_ command: DiagnosticDSURumbleCommand) {
        guard let target = wiimotes.first(where: { min(max($0.playerIndex - 1, 0), 3) == command.slot }) else {
            return
        }
        setRumble(id: target.id, enabled: command.intensity > 0)
    }

    private func handleConnectionCountChanged(_ count: Int) {
        if count > 0 {
            phase = .connected(count: count)
            cancelPairingWork()
            refreshSavedWiimotes()

            if automaticScanning, count < 4 {
                resumeScanning(after: 1.0)
            }
        } else if automaticScanning {
            phase = .scanning
            refreshSavedWiimotes()
            resumeScanning(after: 0.5)
        } else {
            phase = .idle
            refreshSavedWiimotes()
        }
    }

    private func isSupportedWiimoteName(_ name: String) -> Bool {
        let normalized = name.uppercased()
        return normalized.contains("NINTENDO RVL-CNT-01") ||
            normalized.contains("RVL-WBC") ||
            normalized == "WIIMOTE"
    }

    private func loadSavedControllerRecords() -> [String: SavedControllerRecord] {
        guard let data = defaults.data(forKey: Keys.savedControllerRecords) else { return [:] }
        let decoded = (try? JSONDecoder().decode([String: SavedControllerRecord].self, from: data)) ?? [:]
        var normalized: [String: SavedControllerRecord] = [:]
        for (address, record) in decoded {
            let key = normalizedBluetoothAddress(address)
            normalized[key] = mergedControllerRecord(normalized[key], with: record)
        }
        return normalized
    }

    private func saveSavedControllerRecords() {
        guard let data = try? JSONEncoder().encode(savedControllerRecords) else { return }
        defaults.set(data, forKey: Keys.savedControllerRecords)
    }

    private func normalizedBluetoothAddress(_ address: String) -> String {
        address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "-")
            .lowercased()
    }

    private func mergedControllerRecord(
        _ existing: SavedControllerRecord?,
        with incoming: SavedControllerRecord
    ) -> SavedControllerRecord {
        var result = existing ?? SavedControllerRecord()
        if incoming.remoteKind != .unknown {
            result.remoteKind = incoming.remoteKind
        }
        if incoming.motionPlusCapability != .unknown {
            result.motionPlusCapability = incoming.motionPlusCapability
        }
        for extensionRecord in incoming.extensions {
            if let index = result.extensions.firstIndex(where: { $0.identifierHex == extensionRecord.identifierHex }) {
                if extensionRecord.lastSeen > result.extensions[index].lastSeen {
                    result.extensions[index] = extensionRecord
                }
            } else {
                result.extensions.append(extensionRecord)
            }
        }
        return result
    }

    private func persistObservedControllerRecords(from snapshots: [ConnectedWiimoteSnapshot]) {
        var changed = false

        for snapshot in snapshots {
            guard let normalizedAddress = persistenceAddress(for: snapshot) else { continue }
            var record = savedControllerRecords[normalizedAddress] ?? SavedControllerRecord()

            if snapshot.remoteKind != .unknown, record.remoteKind != snapshot.remoteKind {
                record.remoteKind = snapshot.remoteKind
                changed = true
            }
            if snapshot.motionPlusCapability != .unknown,
               record.motionPlusCapability != snapshot.motionPlusCapability {
                record.motionPlusCapability = snapshot.motionPlusCapability
                changed = true
            }

            if snapshot.remoteKind != .balanceBoard,
               let identifierHex = snapshot.extensionIdentifierHex,
               let extensionName = snapshot.extensionName,
               !identifierHex.isEmpty {
                let now = Date()
                if let index = record.extensions.firstIndex(where: { $0.identifierHex == identifierHex }) {
                    if record.extensions[index].name != extensionName ||
                        now.timeIntervalSince(record.extensions[index].lastSeen) > 60 {
                        record.extensions[index] = SavedExtensionRecord(
                            identifierHex: identifierHex,
                            name: extensionName,
                            lastSeen: now
                        )
                        changed = true
                    }
                } else {
                    record.extensions.append(SavedExtensionRecord(
                        identifierHex: identifierHex,
                        name: extensionName,
                        lastSeen: now
                    ))
                    changed = true
                }
            }

            savedControllerRecords[normalizedAddress] = record
        }

        if changed {
            saveSavedControllerRecords()
        }
    }

    private func persistenceAddress(for snapshot: ConnectedWiimoteSnapshot) -> String? {
        if let address = snapshot.address, !address.isEmpty {
            return normalizedBluetoothAddress(address)
        }

        let connectedSavedRemotes = savedWiimotes.filter(\.isConnected)
        if connectedSavedRemotes.count == 1 {
            return normalizedBluetoothAddress(connectedSavedRemotes[0].address)
        }

        return nil
    }

    private func refreshSavedWiimotes() {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let connectedByAddress = Dictionary(uniqueKeysWithValues: wiimotes.compactMap { snapshot in
            snapshot.address.map { (normalizedBluetoothAddress($0), snapshot) }
        })
        let connectedAddresses = Set(connectedByAddress.keys)

        savedWiimotes = devices.compactMap { device in
            guard let name = device.name, isSupportedWiimoteName(name), let address = device.addressString else {
                return nil
            }
            let normalizedAddress = normalizedBluetoothAddress(address)
            let record = savedControllerRecords[normalizedAddress]
            let connectedSnapshot = connectedSnapshot(
                for: normalizedAddress,
                name: name,
                isConnected: device.isConnected() || connectedAddresses.contains(normalizedAddress),
                connectedByAddress: connectedByAddress
            )
            let remoteKind = connectedSnapshot?.remoteKind ??
                record?.remoteKind ??
                WiimoteRemoteKind(name: name, productID: nil)
            let motionPlusCapability = connectedSnapshot?.motionPlusCapability ??
                record?.motionPlusCapability ??
                WiimoteMotionPlusCapability(remoteKind: remoteKind)
            let extensions = remoteKind == .balanceBoard ? [] : savedExtensionSnapshots(
                address: normalizedAddress,
                record: record,
                connectedSnapshot: connectedSnapshot
            )
            return SavedWiimoteSnapshot(
                id: address,
                name: name,
                address: address,
                isConnected: device.isConnected() || connectedAddresses.contains(normalizedAddress),
                remoteKind: remoteKind,
                motionPlusCapability: motionPlusCapability,
                extensions: extensions
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func connectedSnapshot(
        for normalizedAddress: String,
        name: String,
        isConnected: Bool,
        connectedByAddress: [String: ConnectedWiimoteSnapshot]
    ) -> ConnectedWiimoteSnapshot? {
        if let snapshot = connectedByAddress[normalizedAddress] {
            return snapshot
        }
        guard isConnected else { return nil }

        let addresslessSnapshots = wiimotes.filter { $0.address?.isEmpty ?? true }
        if addresslessSnapshots.count == 1 {
            return addresslessSnapshots[0]
        }
        return wiimotes.first { $0.name == name }
    }

    private func savedExtensionSnapshots(
        address: String,
        record: SavedControllerRecord?,
        connectedSnapshot: ConnectedWiimoteSnapshot?
    ) -> [SavedExtensionSnapshot] {
        var extensions = record?.extensions ?? []
        if let identifierHex = connectedSnapshot?.extensionIdentifierHex,
           let name = connectedSnapshot?.extensionName,
           !identifierHex.isEmpty {
            let liveRecord = SavedExtensionRecord(identifierHex: identifierHex, name: name, lastSeen: Date())
            if let index = extensions.firstIndex(where: { $0.identifierHex == identifierHex }) {
                extensions[index] = liveRecord
            } else {
                extensions.append(liveRecord)
            }
        }

        return extensions
            .sorted { $0.lastSeen > $1.lastSeen }
            .map {
                SavedExtensionSnapshot(
                    id: address + ":" + $0.identifierHex,
                    name: $0.name,
                    identifierHex: $0.identifierHex,
                    lastSeen: $0.lastSeen
                )
            }
    }

    private func handleDiscoveredDevice(_ device: IOBluetoothDevice) {
        guard let name = device.name, isSupportedWiimoteName(name) else { return }

        let address = device.addressString ?? name
        diagnostics.append("👀", "Found \(name) at \(address).")

        if device.isPaired() {
            let now = Date()
            if let cooldown = connectionCooldowns[address], cooldown > now {
                return
            }
            connectionCooldowns[address] = now.addingTimeInterval(5)
            stopInquiry(reason: "paired remote found")
            isScanning = false
            diagnostics.append("ℹ️", "The remote is already paired; requesting a HID connection.")
            if !device.isConnected() {
                let result = device.openConnection()
                if result != kIOReturnSuccess {
                    diagnostics.append("⚠️", "Open connection returned \(hex(result)).")
                }
            }
            phase = .waitingForHID(name: name)
            scheduleHIDWaitTimeout(name: name, address: address)
            refreshSavedWiimotes()
            return
        }

        if let cooldown = pairingCooldowns[address], cooldown > Date() {
            return
        }
        guard pairingBridge == nil else { return }
        beginPairing(device: device, name: name, address: address)
    }

    private func beginPairing(
        device: IOBluetoothDevice,
        name: String,
        address: String
    ) {
        stopInquiry(reason: "pairing started")
        isScanning = false
        retryWorkItem?.cancel()
        retryWorkItem = nil

        let attempt = (pairingAttempts[address] ?? 0) + 1
        pairingAttempts[address] = attempt
        phase = .pairing(name: name, attempt: attempt)
        diagnostics.append("🔐", "Starting binary-PIN pairing attempt \(attempt) for \(address).")

        let token = UUID()
        activePairingToken = token
        let bridge = WMPairingBridge(
            device: device,
            logHandler: { [weak self] message in
                self?.diagnostics.append("🔑", message)
            },
            completion: { [weak self] result, detail in
                self?.finishPairing(
                    token: token,
                    device: device,
                    name: name,
                    address: address,
                    result: result,
                    detail: detail
                )
            }
        )
        pairingBridge = bridge

        let startResult = bridge.start()
        if startResult != kIOReturnSuccess {
            finishPairing(
                token: token,
                device: device,
                name: name,
                address: address,
                result: startResult,
                detail: nil
            )
        }
    }

    private func finishPairing(
        token: UUID,
        device: IOBluetoothDevice,
        name: String,
        address: String,
        result: IOReturn,
        detail: String?
    ) {
        guard activePairingToken == token else { return }
        activePairingToken = nil
        pairingBridge?.cancel()
        pairingBridge = nil

        if result == kIOReturnSuccess {
            retryWorkItem?.cancel()
            retryWorkItem = nil
            pairingAttempts[address] = nil
            pairingCooldowns[address] = nil
            phase = .waitingForHID(name: name)
            diagnostics.append("✅", "Pairing succeeded; waiting for the HID service.")
            diagnostics.append("ℹ", "Connection can take a moment. If HID does not appear and the LEDs stop blinking, press a face button again while Scan remains on. Use red SYNC only to pair from scratch.")

            if !device.isConnected() {
                let openResult = device.openConnection()
                if openResult != kIOReturnSuccess {
                    diagnostics.append("⚠️", "Post-pair connection returned \(hex(openResult)).")
                }
            }
            scheduleHIDWaitTimeout(name: name, address: address)
            refreshSavedWiimotes()
            return
        }

        let attempt = pairingAttempts[address] ?? 1
        let explanation = detail?.isEmpty == false ? detail! : hex(result)
        diagnostics.append("❌", "Pairing attempt \(attempt) failed: \(explanation).")

        if attempt < 2 {
            pairingCooldowns[address] = Date().addingTimeInterval(2)
            phase = .error("Pairing failed once; one bounded retry is scheduled.")

            let retry = DispatchWorkItem { [weak self, weak device] in
                guard let self, let device else { return }
                self.retryWorkItem = nil
                guard self.centralManager?.state == .poweredOn else { return }
                self.beginPairing(device: device, name: name, address: address)
            }
            retryWorkItem = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: retry)
        } else {
            retryWorkItem = nil
            pairingAttempts[address] = nil
            pairingCooldowns[address] = Date().addingTimeInterval(30)
            phase = .error("Pairing failed twice. Press SYNC and use Retry when ready.")
            resumeScanning(after: 3)
        }
    }

    private func cancelPairingWork() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        hidWaitWorkItem?.cancel()
        hidWaitWorkItem = nil
        hidWaitRecoveryWorkItem?.cancel()
        hidWaitRecoveryWorkItem = nil
        pairingBridge?.cancel()
        pairingBridge = nil
        activePairingToken = nil
    }

    private func scheduleHIDWaitTimeout(name: String, address: String?) {
        hidWaitWorkItem?.cancel()
        hidWaitRecoveryWorkItem?.cancel()
        let countBefore = wiimotes.count
        if let address {
            let recovery = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hidWaitRecoveryWorkItem = nil
                guard self.wiimotes.count == countBefore else { return }

                self.diagnostics.append(
                    "ℹ",
                    "HID did not appear for \(name); waiting 1 second before sending the Wiiuse-style Bluetooth disconnect."
                )

                let disconnect = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.hidWaitRecoveryWorkItem = nil
                    self.hidWaitWorkItem?.cancel()
                    self.hidWaitWorkItem = nil
                    guard self.wiimotes.count == countBefore else { return }

                    self.sendUnreadyBluetoothDisconnect(name: name, address: address)
                    self.phase = self.automaticScanning ? .scanning : .idle
                    self.refreshSavedWiimotes()
                    self.resumeScanning(after: 0.75)
                }
                self.hidWaitRecoveryWorkItem = disconnect
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: disconnect)
            }
            hidWaitRecoveryWorkItem = recovery
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: recovery)
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hidWaitWorkItem = nil
            self.hidWaitRecoveryWorkItem?.cancel()
            self.hidWaitRecoveryWorkItem = nil
            guard self.wiimotes.count == countBefore else { return }
            self.phase = .error("\(name) paired, but its HID connection did not appear.")
            self.diagnostics.append(
                "",
                "Pairing completed without a HID match. Keep Scan on; press a face button again if the remote turned off or its LEDs stopped blinking. Use red SYNC only if you need to pair from scratch again."
            )
            self.resumeScanning(after: 1)
        }
        hidWaitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    private func sendUnreadyBluetoothDisconnect(name: String, address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            diagnostics.append(
                "⚠",
                "Could not send Wiiuse-style Bluetooth disconnect for \(name); saved address \(address) no longer resolves."
            )
            return
        }

        let wasConnected = device.isConnected()
        diagnostics.append(
            "ℹ",
            "Sending Wiiuse-style Bluetooth disconnect to uninitialized \(name) at \(address): closeConnection()."
        )
        let closeResult = device.closeConnection()
        if closeResult == kIOReturnSuccess {
            diagnostics.append(
                "✅",
                "Bluetooth disconnect sent to \(name); keep Scan on and press a face button again if the remote turns off or its LEDs stop blinking."
            )
        } else if !wasConnected {
            diagnostics.append(
                "ℹ",
                "Bluetooth disconnect for \(name) returned \(hex(closeResult)); the device was already disconnected. Keep Scan on and press a face button again if its LEDs stop blinking."
            )
        } else {
            diagnostics.append("⚠", "Bluetooth disconnect for \(name) returned \(hex(closeResult)).")
        }
    }

    private func resumeScanning(after delay: TimeInterval) {
        guard automaticScanning else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startScanning()
        }
    }

    private func stopInquiry(reason: String) {
        guard let inquiry else { return }
        inquiryStopReason = reason
        suppressInquiryCompletionUntil = Date().addingTimeInterval(0.75)
        inquiry.stop()
    }

    private func resetInquiryIfNeeded(_ completedInquiry: IOBluetoothDeviceInquiry) {
        if inquiry === completedInquiry {
            inquiry = nil
            isScanning = false
        }
    }

    private func bluetoothRuntimeSummary(inquiryResult: IOReturn? = nil) -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown bundle"
        let executable = Bundle.main.executablePath ?? "unknown executable"
        let entitlement = booleanEntitlement("com.apple.security.device.bluetooth") ? "present" : "missing"
        let coreBluetooth = centralManager.map { bluetoothStateName($0.state) } ?? "not created"

        var parts = [
            "bundle=\(bundleID)",
            "executable=\(executable)",
            "bluetooth entitlement=\(entitlement)",
            "CoreBluetooth=\(coreBluetooth)"
        ]

        if let inquiryResult {
            parts.append("Classic inquiry=\(hex(inquiryResult)) \(machErrorDescription(inquiryResult))")
            if inquiryResult == kIOReturnNotPermitted {
                parts.append("CoreBluetooth is authorized but Classic inquiry was denied; suspect macOS TCC/signature policy for this exact app build rather than Wii protocol parsing. For local ad-hoc installs, quit and re-sign the exact app bundle before launching again, for example: codesign --force --deep --sign - /Applications/WiiMacMote.app")
            }
        }

        return parts.joined(separator: " | ")
    }

    private func booleanEntitlement(_ entitlement: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault),
              let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil)
        else {
            return false
        }

        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return false
    }

    private func bluetoothStateName(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "powered off"
        case .poweredOn: return "powered on"
        @unknown default: return "future state"
        }
    }

    private func machErrorDescription(_ value: IOReturn) -> String {
        guard let message = mach_error_string(value) else { return "" }
        return String(cString: message)
    }

    private func hex(_ value: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: value))
    }
}

extension WiimoteManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            diagnostics.append("✅", "Bluetooth is powered on and permission is available.")
            diagnostics.append("ℹ️", bluetoothRuntimeSummary())
            if automaticScanning {
                startScanning()
            } else {
                phase = wiimotes.isEmpty ? .idle : .connected(count: wiimotes.count)
            }

        case .poweredOff:
            stopScanning()
            cancelPairingWork()
            phase = .bluetoothOff
            diagnostics.append("⚠️", "Bluetooth is turned off.")

        case .unauthorized:
            stopScanning()
            cancelPairingWork()
            phase = .permissionDenied
            diagnostics.append("❌", "Bluetooth permission was denied in Privacy & Security.")
            diagnostics.append("ℹ️", bluetoothRuntimeSummary())

        case .unsupported:
            stopScanning()
            cancelPairingWork()
            phase = .error("This Mac does not expose a supported Bluetooth controller.")

        case .resetting:
            stopScanning()
            cancelPairingWork()
            phase = .starting
            diagnostics.append("ℹ️", "Bluetooth is resetting; scanning will resume automatically.")

        case .unknown:
            phase = .starting

        @unknown default:
            phase = .error("Bluetooth entered an unknown state.")
        }
    }
}

extension WiimoteManager: IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryStarted(_ sender: IOBluetoothDeviceInquiry!) {
        isScanning = true
    }

    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard let device else { return }
        handleDiscoveredDevice(device)
    }

    func deviceInquiryDeviceNameUpdated(
        _ sender: IOBluetoothDeviceInquiry!,
        device: IOBluetoothDevice!,
        devicesRemaining: UInt32
    ) {
        guard let device else { return }
        handleDiscoveredDevice(device)
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        let now = Date()
        let stopReason = inquiryStopReason
        inquiryStopReason = nil
        let wasRecentlyStopped = suppressInquiryCompletionUntil.map { $0 > now } ?? false
        if let deadline = suppressInquiryCompletionUntil, deadline <= now {
            suppressInquiryCompletionUntil = nil
        }
        isScanning = false

        // Some macOS Classic Bluetooth paths report KERN_INVALID_ADDRESS (0x1)
        // for empty or interrupted inquiry completion even though discovery can continue.
        let benignInvalidAddressCompletion = error == IOReturn(1)
        if error != kIOReturnSuccess,
           !aborted,
           stopReason == nil,
           !wasRecentlyStopped,
           !benignInvalidAddressCompletion {
            diagnostics.append("⚠️", "Bluetooth inquiry completed with \(hex(error)).")
            diagnostics.append("ℹ️", bluetoothRuntimeSummary(inquiryResult: error))
        }

        if stopReason == nil, (aborted || error != kIOReturnSuccess) {
            resetInquiryIfNeeded(sender)
        }

        guard stopReason == nil,
              automaticScanning,
              pairingBridge == nil,
              wiimotes.count < 4 else {
            return
        }
        sender.clearFoundDevices()
        let resumeDelay: TimeInterval = aborted || wasRecentlyStopped ? 0.75 : 1
        resumeScanning(after: resumeDelay)
    }
}
