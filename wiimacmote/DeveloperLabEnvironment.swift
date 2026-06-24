import Foundation
#if os(macOS)
import Darwin
import Security
#endif

struct DeveloperLabEnvironmentSnapshot: Sendable {
    let virtualHIDEntitlementVisible: Bool
    let bootArgumentsReadable: Bool
    let amfiRelaxationHintDetected: Bool
    let bootArguments: String?
    let teamIdentifier: String?

    var entitlementSummary: String {
        virtualHIDEntitlementVisible
            ? "Restricted virtual-HID entitlement is visible to the running task."
            : "Restricted virtual-HID entitlement is not visible to the running task."
    }

    var signingSummary: String {
        if let teamIdentifier, !teamIdentifier.isEmpty {
            return "Signing team: \(teamIdentifier)."
        }
        return "No Apple team identifier is present (ad-hoc/local signature expected)."
    }

    var amfiSummary: String {
        guard bootArgumentsReadable else {
            return "The running app could not read kern.bootargs; use the included diagnostic script for host checks."
        }
        return amfiRelaxationHintDetected
            ? "The AMFI developer-lab boot-argument hint was detected."
            : "The AMFI developer-lab boot-argument hint was not detected."
    }
}

enum DeveloperLabEnvironment {
    static let virtualHIDEntitlement = "com.apple.developer.hid.virtual.device"
    private static let teamIdentifierEntitlement = "com.apple.developer.team-identifier"

    static func snapshot() -> DeveloperLabEnvironmentSnapshot {
        let bootArguments = readSysctlString("kern.bootargs")
        return DeveloperLabEnvironmentSnapshot(
            virtualHIDEntitlementVisible: hasVirtualHIDEntitlement(),
            bootArgumentsReadable: bootArguments != nil,
            amfiRelaxationHintDetected: bootArguments.map(containsAMFIRelaxation) ?? false,
            bootArguments: bootArguments,
            teamIdentifier: entitlementString(teamIdentifierEntitlement)
        )
    }

    /// Returns whether the entitlement is visible to the current task. This is
    /// more useful at runtime than merely checking the source entitlement file.
    static func hasVirtualHIDEntitlement() -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                  task,
                  virtualHIDEntitlement as CFString,
                  nil
              ) else {
            return false
        }
        return (value as? Bool) == true || (value as? NSNumber)?.boolValue == true
        #else
        return false
        #endif
    }

    /// Pure parser used by both runtime diagnostics and portable tests.
    static func containsAMFIRelaxation(_ bootArguments: String) -> Bool {
        let acceptedValues = Set(["1", "0x1", "0X1", "true", "TRUE"])
        for token in bootArguments.split(whereSeparator: { $0.isWhitespace }) {
            let components = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard components.count == 2,
                  components[0] == "amfi_get_out_of_my_way" else {
                continue
            }
            if acceptedValues.contains(components[1]) {
                return true
            }
        }
        return false
    }

    private static func entitlementString(_ name: String) -> String? {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, name as CFString, nil) else {
            return nil
        }
        return value as? String
        #else
        return nil
        #endif
    }

    private static func readSysctlString(_ name: String) -> String? {
        #if os(macOS)
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: max(size, 1))
        let result = buffer.withUnsafeMutableBytes { bytes in
            sysctlbyname(name, bytes.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }

        return buffer.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return nil }
            return String(cString: baseAddress)
        }
        #else
        return nil
        #endif
    }
}
