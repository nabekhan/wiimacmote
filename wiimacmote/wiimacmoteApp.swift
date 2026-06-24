import SwiftUI

@main
struct WiiMacMoteApp: App {
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
}
