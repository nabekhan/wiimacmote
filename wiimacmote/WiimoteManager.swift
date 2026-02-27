//
//  WiimoteManager.swift
//  wiimacmote
//
//  Handles Wiimote discovery, connection, pairing, and HID input.
//
//  Uses IOBluetoothDeviceInquiry for continuous discovery.
//  Uses IOBluetoothDevicePair (Private API) for Secure Pairing.
//  Uses IOHIDManager (CoreHID) for Input.
//

import Foundation
import IOKit
import IOKit.hid
import IOBluetooth
import Combine

// MARK: - Diagnostic Log

class DiagnosticLog: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let time: Date
        let icon: String
        let message: String
    }

    @Published var entries: [Entry] = []

    func log(_ icon: String, _ message: String) {
        let entry = Entry(time: Date(), icon: icon, message: message)
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > 200 {
                self.entries.removeFirst(self.entries.count - 200)
            }
        }
        print("\(icon) \(message)")
    }

    func clear() {
        DispatchQueue.main.async { self.entries.removeAll() }
    }
}

// MARK: - Discovered Device

struct DiscoveredDevice: Identifiable, Equatable, Hashable {
    let id: String          // address
    let address: String
    let name: String
    let isWiimote: Bool

    var displayName: String {
        if name.isEmpty { return address } else { return name }
    }
}

// MARK: - Connection State

enum WiimoteState: Equatable {
    case idle
    case scanning
    case devicesFound
    case pairing(String)          // address
    case paired(String)           // address
    case connecting
    case connected
    case error(String)

    var description: String {
        switch self {
        case .idle:                 return "Ready"
        case .scanning:            return "Scanning (Press 1+2 or SYNC)..."
        case .devicesFound:        return "Device Found"
        case .pairing:             return "Pairing (PIN Exchange)..."
        case .paired:              return "Paired ✅"
        case .connecting:          return "Waiting for HID..."
        case .connected:           return "Connected ✅"
        case .error(let msg):      return "Error: \(msg)"
        }
    }

    var isWorking: Bool {
        switch self {
        case .scanning, .pairing, .connecting: return true
        default: return false
        }
    }
}

// MARK: - Wiimote Button Bits

private struct WiimoteButtons {
    static let dpadLeft:  UInt16 = 0x0001
    static let dpadRight: UInt16 = 0x0002
    static let dpadDown:  UInt16 = 0x0004
    static let dpadUp:    UInt16 = 0x0008
    static let plus:      UInt16 = 0x0010
    static let two:       UInt16 = 0x0100
    static let one:       UInt16 = 0x0200
    static let b:         UInt16 = 0x0400
    static let a:         UInt16 = 0x0800
    static let minus:     UInt16 = 0x1000
    static let home:      UInt16 = 0x8000
}

// MARK: - WiimoteManager

class WiimoteManager: NSObject, ObservableObject {

    // MARK: Published

    @Published var state: WiimoteState = .idle
    @Published var discoveredDevices: [DiscoveredDevice] = []
    
    struct ConnectedWiimote: Identifiable {
        let id = UUID()
        let device: IOHIDDevice
        let playerIndex: Int
        var gamepad: VirtualGamepad?
        var batteryLevel: Int = -1
        var pressedButtons: Set<String> = []
        var gamepadActive: Bool { gamepad != nil }
    }
    @Published var connectedWiimotes: [ConnectedWiimote] = []
    
    let log = DiagnosticLog()

    // MARK: Private — Bluetooth

    private var inquiry: IOBluetoothDeviceInquiry?
    private var pairingAgent: IOBluetoothDevicePair?
    private var centralManager: CBCentralManager?

    // MARK: Private — HID

    private var hidManager: IOHIDManager?
    
    private var logCancellable: AnyCancellable?
    
    // We keep track of devices we are currently pairing to avoid duplicate attempts
    private var currentlyPairingAddress: String?

    // Focused device for aggressive connection
    private var targetDevice: IOBluetoothDevice?
    private var connectionRetryTimer: Timer?

    // MARK: - Init

    override init() {
        super.init()
        logCancellable = log.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        
        // Initialize CBCentralManager to establish XPC connection for Pairing Coordinator
        centralManager = CBCentralManager(delegate: nil, queue: nil)
        
        setupHIDManager()
    }
    
    deinit {
        stopInquiry()
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    // MARK: - Device Identification

    private func isWiimoteName(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("nintendo rvl-cnt-01") || n.contains("nintendo rvl-wbc") || n == "wiimote"
    }

    // MARK: - Public: Scan

    func startScanning() {
        if state == .scanning && inquiry != nil { return }
        
        log.log("🔍", "Starting Continuous Bluetooth Inquiry...")
        state = .scanning
        startInquiry()
    }
    
    private func startInquiry() {
        if inquiry == nil {
            inquiry = IOBluetoothDeviceInquiry(delegate: self)
            // kIOBluetoothDeviceSearchClassic = 0. We want classic bluetooth.
            // Using 0 implicitly or checking documentation. kIOBluetoothDeviceSearchClassic is defined in headers.
            // In Swift, we can access it via IOBluetoothDeviceInquiry constants if available, or just rely on default.
            // The WiimotePair code sets: _deviceInquiry.searchType = kIOBluetoothDeviceSearchClassic;
            // Let's check if we can set it.
            // IOBluetoothDeviceInquiry doesn't expose searchType property in Swift easily sometimes, but `setSearchCriteria` exists.
            // Actually `init(delegate:)` defaults to Classic.
        }
        
        inquiry?.start()
    }
    
    private func stopInquiry() {
        inquiry?.stop()
        inquiry = nil
        state = .idle
        log.log("🛑", "Scanning stopped")
    }

    // MARK: - Pairing Logic

    private func pairDevice(_ device: IOBluetoothDevice) {
        let address = device.addressString ?? "Unknown"
        
        // Set as target for aggressive retry
        targetDevice = device
        
        if currentlyPairingAddress == address {
            log.log("⚠️", "Already pairing with \(address)")
            return
        }
        
        log.log("🔗", "Found Wiimote: \(device.name ?? "Unknown") (\(address)). Stopping inquiry to pair.")
        
        // Stop inquiry to focus on pairing
        inquiry?.stop()
        
        if device.isPaired() {
             log.log("ℹ️", "Device is already paired. Attempting to connect...")
             // Even if paired, we might need to open connection if it's not connected.
             if !device.isConnected() {
                 device.openConnection()
             }
             // We also want to ensure HID manager picks it up.
             // If connection fails, we might want to unpair and re-pair?
             // For now, let's treat it as a pairing attempt to ensure we have a fresh connection.
             // Actually, WiimotePair skips paired devices. But if user presses SYNC, they probably want to re-pair.
        }
        
        currentlyPairingAddress = address
        state = .pairing(address)
        
        performSecurePairing(device: device)
    }

    func performSecurePairing(device: IOBluetoothDevice) {
        let address = device.addressString ?? "Unknown"
        log.log("🔐", "Initializing IOBluetoothDevicePair for \(address)...")
        
        pairingAgent = IOBluetoothDevicePair(device: device)
        
        guard let agent = pairingAgent else {
            log.log("❌", "Failed to allocate IOBluetoothDevicePair")
            state = .error("Agent alloc failed")
            currentlyPairingAddress = nil
            retryConnection()
            return
        }
        
        agent.delegate = self
        
        log.log("🔧", "Setting UserDefinedPincode = true")
        agent.setUserDefinedPincode(true)
        
        log.log("▶️", "Starting Pairing Agent...")
        let result = agent.start()
        
        if result != kIOReturnSuccess {
            let err = String(cString: mach_error_string(result))
            log.log("❌", "Failed to start pairing. Error code: \(result) (\(err))")
            state = .error("Pairing start failed: \(err)")
            currentlyPairingAddress = nil
            retryConnection()
        } else {
            log.log("⏳", "Pairing agent started. Waiting for PIN request...")
        }
    }
    
    private func retryConnection() {
        if state == .connected { return }
        
        if let target = targetDevice {
             log.log("🔄", "Retrying connection to \(target.name ?? "Target") in 3s...")
             state = .pairing(target.addressString ?? "") // Keep showing pairing state
             
             connectionRetryTimer?.invalidate()
             connectionRetryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                 self?.performSecurePairing(device: target)
             }
        } else {
             resumeScanning()
        }
    }
    
    private func resumeScanning() {
        if state != .connected {
             log.log("🔄", "Resuming scanning...")
             state = .scanning
             inquiry?.start()
        }
    }
    
    func resetTarget() {
        targetDevice = nil
        connectionRetryTimer?.invalidate()
        pairingAgent?.stop()
        pairingAgent = nil
        currentlyPairingAddress = nil
        startScanning()
    }

    // MARK: - Bluetooth Reset
    
    func killBluetoothd() {
        log.log("⚠️", "Attempting to restart bluetoothd...")
        let script = "do shell script \"pkill bluetoothd\" with administrator privileges"
        let appleScript = NSAppleScript(source: script)
        var errorDict: NSDictionary?
        appleScript?.executeAndReturnError(&errorDict)
        if let err = errorDict {
            log.log("❌", "Failed to kill bluetoothd: \(err)")
        } else {
            log.log("✅", "bluetoothd restart requested.")
            // It might take a moment for Bluetooth to come back.
            // We should probably stop scanning and wait a bit.
            stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.startScanning()
            }
        }
    }

    // MARK: - Public: Stop / Disconnect

    func stop() {
        stopInquiry()
        pairingAgent?.stop()
        
        // If we have connected devices, keep the state as connected instead of idle
        if !connectedWiimotes.isEmpty {
            state = .connected
        }
    }

    func disconnectAll() {
        for wiimote in connectedWiimotes {
            IOHIDDeviceClose(wiimote.device, IOOptionBits(kIOHIDOptionsTypeNone))
            wiimote.gamepad?.reset()
        }
        DispatchQueue.main.async {
            self.connectedWiimotes.removeAll()
            self.state = .idle
            self.log.log("🔌", "All disconnected")
        }
    }
    
    func disconnect(playerIndex: Int) {
        guard let index = connectedWiimotes.firstIndex(where: { $0.playerIndex == playerIndex }) else { return }
        let wiimote = connectedWiimotes[index]
        IOHIDDeviceClose(wiimote.device, IOOptionBits(kIOHIDOptionsTypeNone))
        wiimote.gamepad?.reset()
        
        DispatchQueue.main.async {
            self.connectedWiimotes.remove(at: index)
            if self.connectedWiimotes.isEmpty {
                self.state = .idle
            }
            self.log.log("🔌", "Disconnected P\(playerIndex)")
        }
    }

    // MARK: - IOHIDManager Logic

    private func setupHIDManager() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else { return }

        let vid = 0x057E
        let pid1 = 0x0306
        let pid2 = 0x0330
        let matchingDict1 = [kIOHIDVendorIDKey: vid, kIOHIDProductIDKey: pid1] as CFDictionary
        let matchingDict2 = [kIOHIDVendorIDKey: vid, kIOHIDProductIDKey: pid2] as CFDictionary

        IOHIDManagerSetDeviceMatchingMultiple(manager, [matchingDict1, matchingDict2] as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, res, sender, dev in
            guard let ctx = ctx else { return }
            Unmanaged<WiimoteManager>.fromOpaque(ctx).takeUnretainedValue().deviceMatched(dev)
        }, context)
        
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, res, sender, dev in
            guard let ctx = ctx else { return }
            Unmanaged<WiimoteManager>.fromOpaque(ctx).takeUnretainedValue().deviceRemoved(dev)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        log.log("👀", "HID Manager Ready")
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        log.log("✅", "HID Device Matched!")
        if connectedWiimotes.contains(where: { $0.device === device }) { return }
        if connectedWiimotes.count >= 4 { 
            log.log("⚠️", "Max 4 Wiimotes already connected.")
            return 
        }

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            log.log("❌", "Failed to open HID: \(String(format: "0x%08x", result))")
            return
        }
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        let reportCallback: IOHIDReportCallback = { ctx, res, sender, type, rId, report, len in
            guard let ctx = ctx else { return }
            guard let sender = sender else { return }
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            let data = Data(bytes: report, count: len)
            Unmanaged<WiimoteManager>.fromOpaque(ctx).takeUnretainedValue().handleReport(device: device, data: data)
        }
        
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, reportCallback, context)
        onConnected(device: device)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        if let index = connectedWiimotes.firstIndex(where: { $0.device === device }) {
            let playerIndex = connectedWiimotes[index].playerIndex
            log.log("🔌", "HID Device Removed P\(playerIndex)")
            disconnect(playerIndex: playerIndex)
            if connectedWiimotes.isEmpty {
                startScanning()
            }
        }
    }

    private func onConnected(device: IOHIDDevice) {
        // Find first available slot (1-4)
        var availableSlot = 1
        for i in 1...4 {
            if !connectedWiimotes.contains(where: { $0.playerIndex == i }) {
                availableSlot = i
                break
            }
        }
        
        DispatchQueue.main.async {
            if let gp = VirtualGamepad() {
                let newWiimote = ConnectedWiimote(device: device, playerIndex: availableSlot, gamepad: gp)
                self.connectedWiimotes.append(newWiimote)
                self.log.log("🎮", "Virtual Gamepad Active for P\(availableSlot)")
            } else {
                let newWiimote = ConnectedWiimote(device: device, playerIndex: availableSlot, gamepad: nil)
                self.connectedWiimotes.append(newWiimote)
            }
            self.state = .connected
            
            // Send initial reports right after appending to ensure device knows its LED
            self.setReportMode(device: device)
            self.requestStatus(device: device)
            self.setLEDs(device: device, mask: self.getLEDMask(for: availableSlot))
        }
        
        // Ensure pairing agent is cleaned up
        currentlyPairingAddress = nil
        pairingAgent = nil
        
        // We can keep scanning if we want to allow more to pair! 
        // Let's resume scanning after 1 second if we have < 4 Wiimotes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if let self = self, self.connectedWiimotes.count < 4 {
                self.resumeScanning()
            }
        }
    }

    private func sendReport(device: IOHIDDevice, data: [UInt8]) {
        guard data.count >= 2 else { return }
        
        // IOHIDDeviceSetReport expects the report ID to be the FIRST byte in the buffer for Bluetooth HID.
        // It DOES NOT add the report ID itself for Bluetooth devices.
        // We drop 0xA2 because 0xA2 is just the Bluetooth output report identifier for classic Bluetooth,
        // which the macOS Bluetooth HID driver handles internally.
        // What remains is the Wiimote Report ID (e.g., 0x11) followed by the payload.
        let payload = Array(data.dropFirst()) 
        let reportID = CFIndex(payload[0]) // e.g. 0x11
        
        let result = payload.withUnsafeBytes { ptr -> IOReturn in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, ptr.baseAddress!, ptr.count)
        }
        
        if result != kIOReturnSuccess {
            log.log("❌", "sendReport failed: \(String(format: "0x%08x", result))")
        }
    }

    private func setReportMode(device: IOHIDDevice) { sendReport(device: device, data: [0xA2, 0x12, 0x04, 0x30]) }
    private func requestStatus(device: IOHIDDevice) { sendReport(device: device, data: [0xA2, 0x15, 0x00]) }
    
    private func getLEDMask(for playerIndex: Int) -> UInt8 {
        switch playerIndex {
        case 1: return 0x10 // LED 1
        case 2: return 0x20 // LED 2
        case 3: return 0x40 // LED 3
        case 4: return 0x80 // LED 4
        default: return 0x10
        }
    }
    
    func setLEDs(device: IOHIDDevice, mask: UInt8) { sendReport(device: device, data: [0xA2, 0x11, mask]) }
    
    func setRumble(playerIndex: Int, on: Bool) { 
        guard let wiimote = connectedWiimotes.first(where: { $0.playerIndex == playerIndex }) else { return }
        let mask = getLEDMask(for: playerIndex)
        // Rumble is Bit 0 (0x01)
        sendReport(device: wiimote.device, data: [0xA2, 0x11, on ? (mask | 0x01) : mask]) 
    }

    private func handleReport(device: IOHIDDevice, data: Data) {
        guard data.count > 0 else { return }
        switch data[0] {
        case 0x30, 0x31:
            guard data.count >= 3 else { return }
            handleButtons(device: device, raw: UInt16(data[1]) | (UInt16(data[2]) << 8))
        case 0x20:
            guard data.count >= 7 else { return }
            let pct = Int((Float(data[6]) / 200.0) * 100.0)
            DispatchQueue.main.async {
                if let index = self.connectedWiimotes.firstIndex(where: { $0.device === device }) {
                    self.connectedWiimotes[index].batteryLevel = pct
                    let pIndex = self.connectedWiimotes[index].playerIndex
                    self.setLEDs(device: device, mask: self.getLEDMask(for: pIndex))
                }
            }
        default: break
        }
    }

    private func handleButtons(device: IOHIDDevice, raw: UInt16) {
        var x: Int8 = 0; var y: Int8 = 0
        
        let left = (raw & WiimoteButtons.dpadLeft != 0)
        let right = (raw & WiimoteButtons.dpadRight != 0)
        let up = (raw & WiimoteButtons.dpadUp != 0)
        let down = (raw & WiimoteButtons.dpadDown != 0)
        
        if left { x = -127 }
        if right { x = 127 }
        if up { y = -127 }
        if down { y = 127 }

        var mask: UInt16 = 0
        if raw & WiimoteButtons.a != 0 { mask |= VirtualGamepad.Button.a.mask }
        if raw & WiimoteButtons.b != 0 { mask |= VirtualGamepad.Button.b.mask }
        if raw & WiimoteButtons.one != 0 { mask |= VirtualGamepad.Button.x.mask }
        if raw & WiimoteButtons.two != 0 { mask |= VirtualGamepad.Button.y.mask }
        if raw & WiimoteButtons.plus != 0 { mask |= VirtualGamepad.Button.plus.mask }
        if raw & WiimoteButtons.minus != 0 { mask |= VirtualGamepad.Button.minus.mask }
        if raw & WiimoteButtons.home != 0 { mask |= VirtualGamepad.Button.home.mask }

        DispatchQueue.main.async {
            if let index = self.connectedWiimotes.firstIndex(where: { $0.device === device }) {
                self.connectedWiimotes[index].gamepad?.update(xAxis: x, yAxis: y, dpad: (up, down, left, right), buttons: mask)
                
                var s = Set<String>()
                if raw & WiimoteButtons.a != 0 { s.insert("A") }
                if raw & WiimoteButtons.b != 0 { s.insert("B") }
                if raw & WiimoteButtons.one != 0 { s.insert("1") }
                if raw & WiimoteButtons.two != 0 { s.insert("2") }
                if raw & WiimoteButtons.plus != 0 { s.insert("+") }
                if raw & WiimoteButtons.minus != 0 { s.insert("-") }
                if raw & WiimoteButtons.home != 0 { s.insert("⌂") }
                if raw & WiimoteButtons.dpadLeft != 0 { s.insert("←") }
                if raw & WiimoteButtons.dpadRight != 0 { s.insert("→") }
                if raw & WiimoteButtons.dpadUp != 0 { s.insert("↑") }
                if raw & WiimoteButtons.dpadDown != 0 { s.insert("↓") }
                
                self.connectedWiimotes[index].pressedButtons = s
            }
        }
    }
}

// MARK: - IOBluetoothDeviceInquiryDelegate

extension WiimoteManager: IOBluetoothDeviceInquiryDelegate {
    
    func deviceInquiryStarted(_ sender: IOBluetoothDeviceInquiry!) {
        log.log("🔎", "Inquiry Started...")
    }
    
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard let device = device, let name = device.name else { return }
        log.log("👀", "Discovered: \(name) (\(device.addressString ?? "?"))")
        
        if isWiimoteName(name) {
            pairDevice(device)
        }
    }
    
    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        log.log("🏁", "Inquiry Complete. Aborted: \(aborted), Error: \(error)")
        
        // Continuous scanning: Restart if not aborted and no error
        if !aborted && error == kIOReturnSuccess && state == .scanning {
             // Avoid tight loop if something is wrong
             DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                 guard let self = self else { return }
                 if self.state == .scanning {
                     self.log.log("🔄", "Restarting Inquiry...")
                     self.inquiry?.start()
                 }
             }
        }
    }
}

// MARK: - IOBluetoothDevicePairDelegate

extension WiimoteManager: IOBluetoothDevicePairDelegate {
    
    func devicePairingPINCodeRequest(_ sender: Any!) {
        log.log("⚡️", "Delegate: devicePairingPINCodeRequest called")
        
        guard let pair = sender as? IOBluetoothDevicePair else {
            log.log("❌", "Sender is not IOBluetoothDevicePair")
            return
        }
        guard let device = pair.device() else {
            log.log("❌", "Pairing agent has no device")
            return
        }
        
        log.log("🔑", "Calculating PIN for Host Address...")
        
        guard let hostController = IOBluetoothHostController.default() else {
            log.log("❌", "IOBluetoothHostController.default() returned nil")
            return
        }
        
        guard let hostAddressStr = hostController.addressAsString() else {
            log.log("❌", "Host address string is nil")
            return
        }
        
        log.log("ℹ️", "Host Address: \(hostAddressStr)")
        
        var hostAddr = BluetoothDeviceAddress()
        IOBluetoothNSStringToDeviceAddress(hostAddressStr, &hostAddr)
        
        // Reverse address for PIN
        let d = hostAddr.data
        let bytes: [UInt8] = [d.5, d.4, d.3, d.2, d.1, d.0]
        let hexString = bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
        log.log("ℹ️", "Calculated PIN Bytes: \(hexString)")
        
        // Pad to 8 bytes for UInt64
        let paddedBytes = bytes + [0, 0]
        var val: UInt64 = 0
        Data(paddedBytes).withUnsafeBytes { val = $0.load(as: UInt64.self) }
        
        log.log("ℹ️", "PIN as UInt64: \(val)")
        
        guard let coordinator = IOBluetoothCoreBluetoothCoordinator.sharedInstance() else {
            log.log("❌", "IOBluetoothCoreBluetoothCoordinator.sharedInstance() returned nil")
            return
        }
        
        guard let peer = device.classicPeer() else {
            log.log("❌", "device.classicPeer() returned nil")
            return
        }
        
        let type = pair.currentPairingType()
        log.log("ℹ️", "Pairing Type: \(type)")
        
        log.log("📤", "Calling pairPeer on Coordinator...")
        coordinator.pairPeer(peer, forType: type, withKey: NSNumber(value: val))
        log.log("✅", "PIN Sent.")
    }
    
    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        currentlyPairingAddress = nil
        
        if error == kIOReturnSuccess {
            log.log("✅", "Pairing Successful! Waiting for HID connection...")
            state = .paired(pairingAgent?.device()?.addressString ?? "")
            // Inquiry was stopped before pairing.
            // Do NOT restart inquiry immediately, wait for HID connection.
            // But if HID doesn't connect, maybe we should?
            // Usually if paired successfully, the device should connect via HID automatically or we might need to initiate connection.
            // HID Manager device match should happen soon.
            
            // Explicitly try to open connection if it doesn't happen?
            if let device = pairingAgent?.device(), !device.isConnected() {
                 log.log("🔌", "Initiating connection to newly paired device...")
                 device.openConnection()
            }
            
        } else {
            let err = String(cString: mach_error_string(error))
            log.log("❌", "Pairing Failed: Error \(error) (\(err))")
            state = .error("Pairing Failed")
            
            // Retry on failure
            retryConnection()
        }
    }
}

