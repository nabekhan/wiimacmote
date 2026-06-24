import Foundation
import SwiftUI

@main
struct WiiMacMoteApp: App {
    init() {
        applyCommandLineOverrides(ProcessInfo.processInfo.arguments)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 760, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            VStack(alignment: .leading, spacing: 10) {
                Text("WiiMacMote settings are available in the main window.")
                    .font(.headline)
                Text("Keep the main window open while translating Wii Remote input.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 420)
        }
    }

    private func applyCommandLineOverrides(_ arguments: [String]) {
        let defaults = UserDefaults.standard

        if arguments.contains("--enable-virtual-gamepad") {
            defaults.set(true, forKey: "virtualGamepadEnabled")
        }
        if arguments.contains("--disable-virtual-gamepad") {
            defaults.set(false, forKey: "virtualGamepadEnabled")
        }
        if arguments.contains("--no-auto-scan") {
            defaults.set(false, forKey: "automaticScanning")
        }

        if let requested = value(after: "--profile", in: arguments),
           let identity = profile(named: requested) {
            defaults.set(identity.rawValue, forKey: "virtualGamepadIdentity")
        }

        if let requested = value(after: "--backend", in: arguments),
           let backend = backend(named: requested) {
            defaults.set(backend.rawValue, forKey: "virtualGamepadBackendPreference")
        }

        if arguments.contains("--lab-diagnostics") {
            let snapshot = DeveloperLabEnvironment.snapshot()
            print("WiiMacMote Local AMFI Lab diagnostics")
            print("  entitlement: \(snapshot.virtualHIDEntitlementVisible ? "visible" : "missing")")
            print("  signing team: \(snapshot.teamIdentifier ?? "none (ad-hoc/local)")")
            print("  AMFI boot hint: \(snapshot.amfiRelaxationHintDetected ? "detected" : "not detected")")
            print("  boot args: \(snapshot.bootArguments ?? "unavailable")")
        }
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private func profile(named name: String) -> VirtualGamepadIdentity? {
        switch name.lowercased() {
        case "generic": return .generic
        case "xbox", "xbox-series", "xboxseries": return .xboxSeries
        case "switch", "switch-pro", "switchpro": return .switchProSimple
        default: return VirtualGamepadIdentity(rawValue: name)
        }
    }

    private func backend(named name: String) -> VirtualGamepadBackendPreference? {
        switch name.lowercased() {
        case "auto", "automatic": return .automatic
        case "iohid", "iohiduserdevice": return .ioHIDUserDevice
        case "corehid": return .coreHID
        default: return VirtualGamepadBackendPreference(rawValue: name)
        }
    }
}
