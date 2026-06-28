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
                Text("Keep the main window open while pairing and checking Wii controllers.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 420)
        }
    }

    private func applyCommandLineOverrides(_ arguments: [String]) {
        let defaults = UserDefaults.standard

        if arguments.contains("--no-auto-scan") {
            defaults.set(false, forKey: "automaticScanning")
        }
    }
}
