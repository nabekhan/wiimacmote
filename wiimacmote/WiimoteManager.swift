import AppKit
import Combine
import CoreBluetooth
import Foundation
import IOBluetooth

final class DiagnosticLog: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let time: Date
        let icon: String
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    func append(_ icon: String, _ message: String) {
        let work = { [weak self] in
            guard let self else { return }
            self.entries.append(Entry(time: Date(), icon: icon, message: message))
            if self.entries.count > 500 {
                self.entries.removeFirst(self.entries.count - 500)
            }
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
        print("\(icon) \(message)")
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
            .map { "\(formatter.string(from: $0.time)) \($0.icon) \($0.message)" }
            .joined(separator: "\n")
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
        case .waitingForHID(let name): return "Waiting for \(name) to expose HID…"
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

final class WiimoteManager: NSObject, ObservableObject {
    @Published private(set) var phase: WiimoteAppPhase = .starting
    @Published private(set) var isScanning = false
    @Published private(set) var wiimotes: [ConnectedWiimoteSnapshot] = []

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

    let diagnostics = DiagnosticLog()

    private enum Keys {
        static let automaticScanning = "automaticScanning"
        static let virtualGamepadEnabled = "virtualGamepadEnabled"
        static let virtualGamepadIdentity = "virtualGamepadIdentity"
        static let virtualGamepadBackendPreference = "virtualGamepadBackendPreference"
        static let controllerProfile = "controllerProfile"
        static let motionRightStickEnabled = "motionRightStickEnabled"
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
    private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.automaticScanning = defaults.object(forKey: Keys.automaticScanning) as? Bool ?? true
        self.virtualGamepadEnabled = defaults.object(forKey: Keys.virtualGamepadEnabled) as? Bool ?? false
        let defaultVirtualIdentity: VirtualGamepadIdentity =
            WiiMacMoteBuildFlavor.isDeveloperLab ? .xboxSeries : .generic
        self.virtualGamepadIdentity = VirtualGamepadIdentity(
            rawValue: defaults.string(forKey: Keys.virtualGamepadIdentity) ?? ""
        ) ?? defaultVirtualIdentity
        let defaultVirtualBackend: VirtualGamepadBackendPreference =
            WiiMacMoteBuildFlavor.isDeveloperLab ? .ioHIDUserDevice : .automatic
        self.virtualGamepadBackendPreference = VirtualGamepadBackendPreference(
            rawValue: defaults.string(forKey: Keys.virtualGamepadBackendPreference) ?? ""
        ) ?? defaultVirtualBackend
        self.motionRightStickEnabled = defaults.object(forKey: Keys.motionRightStickEnabled) as? Bool ?? false
        self.controllerProfile = ControllerProfile(
            rawValue: defaults.string(forKey: Keys.controllerProfile) ?? ""
        ) ?? .sideways
        super.init()
        configureHIDCallbacks()
    }

    deinit {
        cancelPairingWork()
        inquiry?.stop()
        centralManager?.delegate = nil
        hidController.stop()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        hidController.start()
        diagnostics.append(
            "🚀",
            "WiiMacMote 2.0.5 (\(WiiMacMoteBuildFlavor.title)) initialized."
        )

        if WiiMacMoteBuildFlavor.isDeveloperLab {
            let environment = DeveloperLabEnvironment.snapshot()
            diagnostics.append(
                environment.virtualHIDEntitlementVisible ? "✅" : "❌",
                environment.entitlementSummary
            )
            diagnostics.append("🔏", environment.signingSummary)
            diagnostics.append(
                environment.amfiRelaxationHintDetected ? "⚠️" : "ℹ️",
                environment.amfiSummary
            )
        }

        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    func startScanning() {
        guard hasStarted else {
            start()
            return
        }
        guard centralManager?.state == .poweredOn else { return }
        guard pairingBridge == nil, activePairingToken == nil else { return }
        guard retryWorkItem == nil, hidWaitWorkItem == nil else { return }
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

        inquiry.clearFoundDevices()
        let result = inquiry.start()
        guard result == kIOReturnSuccess else {
            phase = .error("Bluetooth scan could not start (\(hex(result))).")
            diagnostics.append("❌", "Classic Bluetooth inquiry failed to start: \(hex(result)).")
            return
        }

        isScanning = true
        if wiimotes.isEmpty {
            phase = .scanning
        }
        diagnostics.append("🔍", "Classic Bluetooth inquiry started. Press the red SYNC button.")
    }

    func stopScanning() {
        inquiry?.stop()
        isScanning = false
        if wiimotes.isEmpty, pairingBridge == nil {
            phase = .idle
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
            motionRightStickEnabled: motionRightStickEnabled
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
        }
        hidController.onConnectionCountChanged = { [weak self] count in
            self?.handleConnectionCountChanged(count)
        }
    }

    private func handleConnectionCountChanged(_ count: Int) {
        if count > 0 {
            phase = .connected(count: count)
            cancelPairingWork()

            if automaticScanning, count < 4 {
                resumeScanning(after: 1.0)
            }
        } else if automaticScanning {
            phase = .scanning
            resumeScanning(after: 0.5)
        } else {
            phase = .idle
        }
    }

    private func isSupportedWiimoteName(_ name: String) -> Bool {
        let normalized = name.uppercased()
        return normalized.contains("NINTENDO RVL-CNT-01") || normalized == "WIIMOTE"
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
            inquiry?.stop()
            isScanning = false
            diagnostics.append("ℹ️", "The remote is already paired; requesting a HID connection.")
            if !device.isConnected() {
                let result = device.openConnection()
                if result != kIOReturnSuccess {
                    diagnostics.append("⚠️", "Open connection returned \(hex(result)).")
                }
            }
            phase = .waitingForHID(name: name)
            scheduleHIDWaitTimeout(name: name)
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
        inquiry?.stop()
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

            if !device.isConnected() {
                let openResult = device.openConnection()
                if openResult != kIOReturnSuccess {
                    diagnostics.append("⚠️", "Post-pair connection returned \(hex(openResult)).")
                }
            }
            scheduleHIDWaitTimeout(name: name)
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
            // Avoid the old infinite loop: two failures trigger a long cooldown
            // and return to discovery instead of hammering the pairing daemon.
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
        pairingBridge?.cancel()
        pairingBridge = nil
        activePairingToken = nil
    }

    private func scheduleHIDWaitTimeout(name: String) {
        hidWaitWorkItem?.cancel()
        let countBefore = wiimotes.count
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hidWaitWorkItem = nil
            guard self.wiimotes.count == countBefore else { return }
            self.phase = .error("\(name) paired, but its HID connection did not appear.")
            self.diagnostics.append(
                "⚠️",
                "Pairing completed without a HID match. Press SYNC again or remove the stale Bluetooth pairing."
            )
            self.resumeScanning(after: 1)
        }
        hidWaitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    private func resumeScanning(after delay: TimeInterval) {
        guard automaticScanning else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startScanning()
        }
    }

    private func hex(_ value: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: value))
    }
}

// MARK: - CoreBluetooth permission/power gate

extension WiimoteManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            diagnostics.append("✅", "Bluetooth is powered on and permission is available.")
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

// MARK: - Classic Bluetooth inquiry

extension WiimoteManager: IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryStarted(_ sender: IOBluetoothDeviceInquiry!) {
        isScanning = true
    }

    func deviceInquiryDeviceFound(
        _ sender: IOBluetoothDeviceInquiry!,
        device: IOBluetoothDevice!
    ) {
        guard let device else { return }
        handleDiscoveredDevice(device)
    }

    func deviceInquiryComplete(
        _ sender: IOBluetoothDeviceInquiry!,
        error: IOReturn,
        aborted: Bool
    ) {
        isScanning = false

        if error != kIOReturnSuccess, !aborted {
            diagnostics.append("⚠️", "Bluetooth inquiry completed with \(hex(error)).")
        }

        guard !aborted, automaticScanning, pairingBridge == nil, wiimotes.count < 4 else {
            return
        }
        sender.clearFoundDevices()
        resumeScanning(after: 1)
    }
}
