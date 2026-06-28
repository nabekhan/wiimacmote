import AppKit
import Combine
import CoreBluetooth
import Foundation
import IOBluetooth

final class DiagnosticLog: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let time: Date
        let level: String
        let symbolName: String
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    func append(_ level: String, _ message: String) {
        let presentation = Self.presentation(for: level)
        let work = { [weak self] in
            guard let self else { return }
            self.entries.append(Entry(
                time: Date(),
                level: presentation.level,
                symbolName: presentation.symbolName,
                message: message
            ))
            if self.entries.count > 120 {
                self.entries.removeFirst(self.entries.count - 120)
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

    private static func presentation(for level: String) -> (level: String, symbolName: String) {
        switch level.lowercased() {
        case "error": return ("Error", "xmark.circle.fill")
        case "warning": return ("Warning", "exclamationmark.triangle.fill")
        case "success": return ("Success", "checkmark.circle.fill")
        case "discovery": return ("Discovery", "dot.radiowaves.left.and.right")
        case "pairing": return ("Pairing", "link.circle.fill")
        case "removal": return ("Removal", "trash.circle.fill")
        case "connection": return ("Connection", "link.circle.fill")
        case "extension": return ("Extension", "puzzlepiece.extension.fill")
        default: return ("Info", "info.circle.fill")
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

    let diagnostics = DiagnosticLog()

    private enum Keys {
        static let automaticScanning = "automaticScanning"
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
    private lazy var hidController = WiimoteHIDController()
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.automaticScanning = defaults.object(forKey: Keys.automaticScanning) as? Bool ?? true
        super.init()
        self.savedControllerRecords = loadSavedControllerRecords()
        configureHIDCallbacks()
    }

    deinit {
        cancelPairingWork()
        stopInquiry(reason: "manager teardown")
        centralManager?.delegate = nil
        hidController.stop()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        hidController.start()
        refreshSavedWiimotes()

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
        guard let state = centralManager?.state else {
            return
        }
        guard state == .poweredOn else {
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
            diagnostics.append("error", "Classic Bluetooth inquiry failed to start: \(hex(result)).")
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
            diagnostics.append("warning", "Saved remote \(address) is no longer available to Bluetooth.")
            refreshSavedWiimotes()
            return
        }

        if device.isConnected() {
            let result = device.closeConnection()
            if result != kIOReturnSuccess {
                diagnostics.append("warning", "Disconnect returned \(hex(result)) for \(address).")
            } else {
                diagnostics.append("connection", "Disconnect requested for \(device.name ?? address).")
            }
        }
        refreshSavedWiimotes()
    }

    func removeSavedWiimote(address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            diagnostics.append("warning", "Saved remote \(address) is no longer available to Bluetooth.")
            refreshSavedWiimotes()
            return
        }

        let name = device.name ?? address
        stopInquiry(reason: "removing saved remote")
        cancelPairingWork()
        if device.isConnected() {
            let closeResult = device.closeConnection()
            if closeResult != kIOReturnSuccess {
                diagnostics.append("warning", "Disconnect before removal returned \(hex(closeResult)) for \(name).")
            }
        }

        diagnostics.append("removal", "Removing \(name) from macOS Bluetooth saved devices.")
        WMDeviceRemovalBridge.removePairing(for: device) { [weak self] result, detail in
            guard let self else { return }
            if result == kIOReturnSuccess {
                self.connectionCooldowns[address] = nil
                self.pairingCooldowns[address] = nil
                self.pairingAttempts[address] = nil
                self.savedControllerRecords[self.normalizedBluetoothAddress(address)] = nil
                self.saveSavedControllerRecords()
                let method = detail?.isEmpty == false ? " via \(detail!)" : ""
                self.diagnostics.append("success", "Removed \(name) from macOS Bluetooth saved devices\(method).")
            } else {
                let explanation = detail?.isEmpty == false ? detail! : self.machErrorDescription(result)
                self.diagnostics.append(
                    "error",
                    "Could not remove \(name) from macOS Bluetooth saved devices: \(self.hex(result)) \(explanation)"
                )
            }
            self.refreshSavedWiimotes()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                self?.refreshSavedWiimotes()
            }
        }
    }

    func removeSavedExtension(remoteAddress: String, identifierHex: String) {
        let address = normalizedBluetoothAddress(remoteAddress)
        guard var record = savedControllerRecords[address] else {
            refreshSavedWiimotes()
            return
        }

        let originalCount = record.extensions.count
        record.extensions.removeAll {
            $0.identifierHex.caseInsensitiveCompare(identifierHex) == .orderedSame
        }
        guard record.extensions.count != originalCount else {
            refreshSavedWiimotes()
            return
        }

        savedControllerRecords[address] = record
        saveSavedControllerRecords()
        refreshSavedWiimotes()
        diagnostics.append("removal", "Removed saved extension \(identifierHex).")
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

    private func configureHIDCallbacks() {
        hidController.logHandler = { [weak self] level, message in
            self?.appendHIDLog(level: level, message: message)
        }
        hidController.onSnapshotsChanged = { [weak self] snapshots in
            self?.wiimotes = snapshots
            self?.persistObservedControllerRecords(from: snapshots)
            self?.refreshSavedWiimotes()
        }
        hidController.onConnectionCountChanged = { [weak self] count in
            self?.handleConnectionCountChanged(count)
        }
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

    private func appendHIDLog(level: String, message: String) {
        if level == "info",
           message == "HID service is ready on its dedicated dispatch queue." {
            return
        }
        if level == "info",
           message.contains("extension state changed") {
            return
        }
        diagnostics.append(level, message)
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
        if device.isPaired() {
            let now = Date()
            if let cooldown = connectionCooldowns[address], cooldown > now {
                return
            }
            connectionCooldowns[address] = now.addingTimeInterval(5)
            stopInquiry(reason: "paired remote found")
            isScanning = false
            diagnostics.append("discovery", "Connecting saved controller \(name).")
            if !device.isConnected() {
                let result = device.openConnection()
                if result != kIOReturnSuccess {
                    diagnostics.append("warning", "Open connection returned \(hex(result)).")
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
        diagnostics.append("pairing", "Pairing \(name) (attempt \(attempt)).")

        let token = UUID()
        activePairingToken = token
        let bridge = WMPairingBridge(
            device: device,
            logHandler: { message in
                print("[Pairing] \(message)")
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
            diagnostics.append("success", "Pairing succeeded; waiting for the HID service.")

            if !device.isConnected() {
                let openResult = device.openConnection()
                if openResult != kIOReturnSuccess {
                    diagnostics.append("warning", "Post-pair connection returned \(hex(openResult)).")
                }
            }
            scheduleHIDWaitTimeout(name: name, address: address)
            refreshSavedWiimotes()
            return
        }

        let attempt = pairingAttempts[address] ?? 1
        let explanation = detail?.isEmpty == false ? detail! : hex(result)
        diagnostics.append("error", "Pairing attempt \(attempt) failed: \(explanation).")

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
            phase = .error("Pairing failed twice.")
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
                "warning",
                "HID service did not appear for \(name) within 10 seconds."
            )
            self.resumeScanning(after: 1)
        }
        hidWaitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    private func sendUnreadyBluetoothDisconnect(name: String, address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            diagnostics.append(
                "warning",
                "Could not close Bluetooth connection for \(name) after HID timeout; saved address \(address) no longer resolves."
            )
            return
        }

        let wasConnected = device.isConnected()
        let closeResult = device.closeConnection()
        if closeResult == kIOReturnSuccess {
            diagnostics.append(
                "connection",
                "Closed Bluetooth connection for \(name) after HID timeout."
            )
        } else if !wasConnected {
            diagnostics.append(
                "connection",
                "HID timeout disconnect skipped for \(name); Bluetooth connection was already closed."
            )
        } else {
            diagnostics.append("warning", "Bluetooth disconnect for \(name) returned \(hex(closeResult)).")
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
            diagnostics.append("success", "Bluetooth ready.")
            if automaticScanning {
                startScanning()
            } else {
                phase = wiimotes.isEmpty ? .idle : .connected(count: wiimotes.count)
            }

        case .poweredOff:
            stopScanning()
            cancelPairingWork()
            phase = .bluetoothOff
            diagnostics.append("warning", "Bluetooth is turned off.")

        case .unauthorized:
            stopScanning()
            cancelPairingWork()
            phase = .permissionDenied
            diagnostics.append("error", "Bluetooth permission was denied in Privacy & Security.")

        case .unsupported:
            stopScanning()
            cancelPairingWork()
            phase = .error("This Mac does not expose a supported Bluetooth controller.")

        case .resetting:
            stopScanning()
            cancelPairingWork()
            phase = .starting
            diagnostics.append("info", "Bluetooth is resetting.")

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
            diagnostics.append("warning", "Bluetooth inquiry completed with \(hex(error)).")
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
