import Darwin
import Foundation
import IOKit
import IOKit.hid
#if canImport(CoreHID)
import CoreHID
#endif

enum WiiMacMoteBuildFlavor {
    #if DEVELOPER_LAB
    static let isDeveloperLab = true
    static let title = "Local AMFI Lab"
    #else
    static let isDeveloperLab = false
    static let title = "Standard"
    #endif
}


enum VirtualGamepadCreationError: LocalizedError {
    case restrictedEntitlementMissing
    case backendUnavailable(VirtualGamepadBackendKind, String)
    case deviceCreationFailed(
        VirtualGamepadBackendKind,
        VirtualGamepadIdentity,
        entitlementVisible: Bool
    )
    case initialReportFailed(VirtualGamepadBackendKind, IOReturn)
    case allBackendsFailed([String])

    var errorDescription: String? {
        switch self {
        case .restrictedEntitlementMissing:
            return "This process does not carry com.apple.developer.hid.virtual.device. Virtual output is available in the app, but macOS will reject it until the app is signed with that entitlement and allowed by the current security policy."
        case .backendUnavailable(let backend, let reason):
            return "\(backend.rawValue) is unavailable: \(reason)"
        case .deviceCreationFailed(let backend, let identity, let entitlementVisible):
            if entitlementVisible {
                return "\(backend.rawValue) could not create the \(identity.shortTitle) device even though the restricted virtual-HID entitlement is visible. Check the Developer Lab preflight output, AMFI state, and the macOS unified log."
            }
            return "\(backend.rawValue) could not create the \(identity.shortTitle) device, and the running task does not expose \(DeveloperLabEnvironment.virtualHIDEntitlement). Sign with that entitlement before testing on an AMFI-relaxed Mac."
        case .initialReportFailed(let backend, let code):
            return "\(backend.rawValue) created the device but rejected its first report (\(Self.hex(code)))."
        case .allBackendsFailed(let failures):
            return "No virtual HID backend succeeded. \(failures.joined(separator: " · "))"
        }
    }

    private static func hex(_ value: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: value))
    }
}

private protocol VirtualGamepadBackend: AnyObject {
    var kind: VirtualGamepadBackendKind { get }

    /// Returns an IOKit result for synchronous backends. `nil` means the report
    /// was accepted into an asynchronous backend queue.
    func submit(_ report: Data) -> IOReturn?
    func cancel()
}

/// Keeps the CF object alive until IOKit runs its asynchronous cancel handler.
private final class IOHIDVirtualDeviceLifetime {
    var device: IOHIDUserDevice?

    init(device: IOHIDUserDevice) {
        self.device = device
    }
}

private final class IOHIDUserDeviceGamepadBackend: VirtualGamepadBackend {
    let kind = VirtualGamepadBackendKind.ioHIDUserDevice

    private let queue: DispatchQueue
    private var device: IOHIDUserDevice?
    private var lifetime: IOHIDVirtualDeviceLifetime?

    init(
        specification: VirtualGamepadSpecification,
        queue: DispatchQueue
    ) throws {
        self.queue = queue

        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey as String: Data(specification.descriptor),
            kIOHIDProductKey as String: specification.productName,
            kIOHIDManufacturerKey as String: specification.manufacturer,
            kIOHIDSerialNumberKey as String: specification.serialNumber,
            kIOHIDVendorIDKey as String: NSNumber(value: specification.vendorID),
            kIOHIDProductIDKey as String: NSNumber(value: specification.productID),
            kIOHIDVersionNumberKey as String: NSNumber(value: specification.versionNumber),
            kIOHIDTransportKey as String: specification.ioKitTransport,
            kIOHIDPrimaryUsagePageKey as String: NSNumber(value: 0x01),
            kIOHIDPrimaryUsageKey as String: NSNumber(value: 0x05)
        ]

        guard let created = IOHIDUserDeviceCreateWithProperties(
            kCFAllocatorDefault,
            properties as CFDictionary,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) else {
            throw VirtualGamepadCreationError.deviceCreationFailed(
                kind,
                specification.identity,
                entitlementVisible: DeveloperLabEnvironment.hasVirtualHIDEntitlement()
            )
        }

        let lifetime = IOHIDVirtualDeviceLifetime(device: created)
        self.device = created
        self.lifetime = lifetime
        IOHIDUserDeviceSetDispatchQueue(created, queue)
        IOHIDUserDeviceSetCancelHandler(created) { [lifetime] in
            lifetime.device = nil
        }
        IOHIDUserDeviceActivate(created)
    }

    deinit {
        cancel()
    }

    func submit(_ report: Data) -> IOReturn? {
        guard let device else { return kIOReturnNotOpen }
        return report.withUnsafeBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.baseAddress else {
                return kIOReturnBadArgument
            }
            return IOHIDUserDeviceHandleReportWithTimeStamp(
                device,
                mach_absolute_time(),
                baseAddress.assumingMemoryBound(to: UInt8.self),
                report.count
            )
        }
    }

    func cancel() {
        guard let device else { return }
        self.device = nil
        IOHIDUserDeviceCancel(device)
    }
}

#if canImport(CoreHID)
@available(macOS 15.0, *)
private final class CoreHIDGamepadBackend: VirtualGamepadBackend {
    let kind = VirtualGamepadBackendKind.coreHID

    private let device: HIDVirtualDevice
    private let delegate: Delegate
    private let stateLock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var worker: Task<Void, Never>?
    private var isCancelled = false

    init(specification: VirtualGamepadSpecification) throws {
        let properties = HIDVirtualDevice.Properties(
            descriptor: Data(specification.descriptor),
            vendorID: UInt32(specification.vendorID),
            productID: UInt32(specification.productID),
            transport: .bluetoothLowEnergy,
            product: specification.productName,
            manufacturer: specification.manufacturer,
            versionNumber: UInt64(specification.versionNumber),
            serialNumber: specification.serialNumber
        )
        guard let created = HIDVirtualDevice(properties: properties) else {
            throw VirtualGamepadCreationError.deviceCreationFailed(
                kind,
                specification.identity,
                entitlementVisible: DeveloperLabEnvironment.hasVirtualHIDEntitlement()
            )
        }

        let delegate = Delegate()
        var capturedContinuation: AsyncStream<Data>.Continuation?
        let stream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(128)) { continuation in
            capturedContinuation = continuation
        }

        self.device = created
        self.delegate = delegate
        self.continuation = capturedContinuation
        self.worker = Task { [created, delegate, stream] in
            await created.activate(delegate: delegate)
            for await report in stream {
                guard !Task.isCancelled else { break }
                do {
                    try await created.dispatchInputReport(data: report, timestamp: .now)
                } catch {
                    let message = "[WiiMacMote] CoreHID report failed: \(error.localizedDescription)\n"
                    FileHandle.standardError.write(Data(message.utf8))
                }
            }
        }
    }

    deinit {
        cancel()
    }

    func submit(_ report: Data) -> IOReturn? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isCancelled, let continuation else { return kIOReturnNotOpen }
        continuation.yield(report)
        return nil
    }

    func cancel() {
        stateLock.lock()
        guard !isCancelled else {
            stateLock.unlock()
            return
        }
        isCancelled = true
        let continuation = self.continuation
        self.continuation = nil
        let worker = self.worker
        self.worker = nil
        stateLock.unlock()

        continuation?.finish()
        worker?.cancel()
    }

    private final class Delegate: HIDVirtualDeviceDelegate, Sendable {
        func hidVirtualDevice(
            _ device: HIDVirtualDevice,
            receivedSetReportRequestOfType type: HIDReportType,
            id: HIDReportID?,
            data: Data
        ) async throws {
            // Output reports (including rumble handshakes) are intentionally
            // ignored in 2.0.5; publishing input remains independent.
        }

        func hidVirtualDevice(
            _ device: HIDVirtualDevice,
            receivedGetReportRequestOfType type: HIDReportType,
            id: HIDReportID?,
            maxSize: Int
        ) async throws -> Data {
            Data()
        }
    }
}
#endif

/// Experimental virtual HID output. A separate canonical state is encoded for
/// each advertised controller identity, while publication is delegated to
/// either IOHIDUserDevice or CoreHID.
final class VirtualGamepad {
    let playerIndex: Int
    let identity: VirtualGamepadIdentity
    let backendKind: VirtualGamepadBackendKind

    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let backend: VirtualGamepadBackend
    private var lastState = VirtualGamepadState.neutral
    private var hasSentState = false

    init(
        playerIndex: Int,
        identity: VirtualGamepadIdentity,
        backendPreference: VirtualGamepadBackendPreference
    ) throws {
        guard DeveloperLabEnvironment.hasVirtualHIDEntitlement() else {
            throw VirtualGamepadCreationError.restrictedEntitlementMissing
        }

        self.playerIndex = playerIndex
        self.identity = identity
        self.queue = DispatchQueue(
            label: "dev.wiimacmote.virtual-gamepad.p\(playerIndex)",
            qos: .userInteractive
        )
        queue.setSpecific(key: queueKey, value: ())

        let specification = VirtualGamepadReports.specification(
            for: identity,
            playerIndex: playerIndex
        )
        let backend = try Self.makeBackend(
            preference: backendPreference,
            specification: specification,
            queue: queue
        )
        self.backend = backend
        self.backendKind = backend.kind

        let initialReports = VirtualGamepadReports.reports(
            for: .neutral,
            identity: identity,
            previousState: nil
        )
        for report in initialReports {
            if let result = backend.submit(report), result != kIOReturnSuccess {
                backend.cancel()
                throw VirtualGamepadCreationError.initialReportFailed(backend.kind, result)
            }
        }
        hasSentState = true
    }

    deinit {
        let operation = { [backend, identity, lastState] in
            for report in VirtualGamepadReports.reports(
                for: .neutral,
                identity: identity,
                previousState: lastState
            ) {
                _ = backend.submit(report)
            }
            backend.cancel()
        }

        if DispatchQueue.getSpecific(key: queueKey) != nil {
            operation()
        } else {
            queue.sync(execute: operation)
        }
    }

    func update(_ state: VirtualGamepadState) {
        enqueue(state, force: false, synchronously: false)
    }

    func reset() {
        enqueue(.neutral, force: true, synchronously: true)
    }

    private func enqueue(
        _ state: VirtualGamepadState,
        force: Bool,
        synchronously: Bool
    ) {
        let operation = { [weak self] in
            guard let self else { return }
            guard force || !self.hasSentState || state != self.lastState else { return }

            let reports = VirtualGamepadReports.reports(
                for: state,
                identity: self.identity,
                previousState: self.hasSentState ? self.lastState : nil
            )
            var accepted = true
            for report in reports {
                if let result = self.backend.submit(report), result != kIOReturnSuccess {
                    accepted = false
                    let message = String(
                        format: "[WiiMacMote] %@ report failed: 0x%08X\n",
                        self.backendKind.rawValue,
                        UInt32(bitPattern: result)
                    )
                    FileHandle.standardError.write(Data(message.utf8))
                    break
                }
            }
            if accepted {
                self.lastState = state
                self.hasSentState = true
            }
        }

        if synchronously {
            if DispatchQueue.getSpecific(key: queueKey) != nil {
                operation()
            } else {
                queue.sync(execute: operation)
            }
        } else {
            queue.async(execute: operation)
        }
    }

    private static func makeBackend(
        preference: VirtualGamepadBackendPreference,
        specification: VirtualGamepadSpecification,
        queue: DispatchQueue
    ) throws -> VirtualGamepadBackend {
        let order: [VirtualGamepadBackendKind]
        switch preference {
        case .automatic:
            order = [.ioHIDUserDevice, .coreHID]
        case .ioHIDUserDevice:
            order = [.ioHIDUserDevice]
        case .coreHID:
            order = [.coreHID]
        }

        var failures: [String] = []
        for kind in order {
            do {
                switch kind {
                case .ioHIDUserDevice:
                    return try IOHIDUserDeviceGamepadBackend(
                        specification: specification,
                        queue: queue
                    )
                case .coreHID:
                    #if canImport(CoreHID)
                    if #available(macOS 15.0, *) {
                        return try CoreHIDGamepadBackend(specification: specification)
                    }
                    throw VirtualGamepadCreationError.backendUnavailable(
                        kind,
                        "macOS 15 or newer is required"
                    )
                    #else
                    throw VirtualGamepadCreationError.backendUnavailable(
                        kind,
                        "this SDK does not include CoreHID"
                    )
                    #endif
                }
            } catch {
                failures.append("\(kind.rawValue): \(error.localizedDescription)")
            }
        }

        if failures.count == 1, let only = failures.first {
            throw VirtualGamepadCreationError.allBackendsFailed([only])
        }
        throw VirtualGamepadCreationError.allBackendsFailed(failures)
    }
}
