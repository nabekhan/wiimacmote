import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var manager = WiimoteManager()
    @State private var selectedSection: SettingsSection? = .controllers
    @State private var savedRemotePendingRemoval: SavedWiimoteSnapshot?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .frame(minWidth: 860, minHeight: 660)
        .onAppear { manager.start() }
        .alert("Forget Saved Controller?", isPresented: savedRemoteRemovalIsPresented) {
            Button("Forget", role: .destructive) {
                if let remote = savedRemotePendingRemoval {
                    manager.removeSavedWiimote(address: remote.address)
                }
                savedRemotePendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                savedRemotePendingRemoval = nil
            }
        } message: {
            if let remote = savedRemotePendingRemoval {
                Text("This removes \(remote.name) from macOS Bluetooth saved devices. Press the red SYNC button to pair it again later.")
            }
        }
    }

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: $selectedSection) { section in
            NavigationLink(value: section) {
                Label(section.title, systemImage: section.systemImage)
            }
        }
        .navigationTitle("WiiMacMote")
        .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selectedSection ?? .controllers {
        case .controllers:
            controllersPage
        case .savedControllers:
            savedControllersPage
        case .output:
            outputPage
        case .bluetooth:
            bluetoothPage
        case .diagnostics:
            diagnosticsPage
        }
    }

    private var controllersPage: some View {
        settingsPage(title: "Game Controllers", subtitle: controllerSubtitle) {
            if manager.wiimotes.isEmpty {
                emptyControllerSection
            } else {
                ForEach(manager.wiimotes) { wiimote in
                    connectedControllerSection(wiimote)
                }
            }

            connectionSection
        }
    }

    private var savedControllersPage: some View {
        settingsPage(title: "Saved Controllers", subtitle: "Controllers remembered by macOS Bluetooth.") {
            if manager.savedWiimotes.isEmpty {
                settingsSection {
                    emptyRow(
                        title: "No saved Wii Remotes",
                        message: "Pair with the red SYNC button to add a controller to this list.",
                        systemImage: "gamecontroller"
                    )
                }
            } else {
                settingsSection("Saved Wii Remotes") {
                    ForEach(manager.savedWiimotes) { remote in
                        savedControllerRow(remote)
                        if remote.id != manager.savedWiimotes.last?.id {
                            rowDivider()
                        }
                    }
                }
            }
        }
    }

    private var outputPage: some View {
        settingsPage(title: "Output", subtitle: "Experimental virtual controller publication and input mapping.") {
            settingsSection("Virtual Controller") {
                settingsRow(title: "Create Virtual Gamepad", detail: "Publishes a user-space virtual HID controller when macOS accepts the entitlement and signature.") {
                    Toggle("", isOn: $manager.virtualGamepadEnabled)
                        .labelsHidden()
                }
                rowDivider()
                settingsRow(title: "Controller Identity", detail: manager.virtualGamepadIdentity.detail) {
                    Picker("Controller Identity", selection: $manager.virtualGamepadIdentity) {
                        ForEach(VirtualGamepadIdentity.allCases) { identity in
                            Text(identity.title + (identity.isRecommended ? " - Recommended" : ""))
                                .tag(identity)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                    .disabled(!manager.virtualGamepadEnabled)
                }
                rowDivider()
                settingsRow(title: "Publication Backend", detail: manager.virtualGamepadBackendPreference.detail) {
                    Picker("Publication Backend", selection: $manager.virtualGamepadBackendPreference) {
                        ForEach(VirtualGamepadBackendPreference.allCases) { backend in
                            Text(backend.title).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                    .disabled(!manager.virtualGamepadEnabled)
                }
            }

            settingsSection("Mapping") {
                settingsRow(title: "Button Profile", detail: manager.controllerProfile.detail) {
                    Picker("Button Profile", selection: $manager.controllerProfile) {
                        ForEach(ControllerProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                    .disabled(!manager.virtualGamepadEnabled)
                }
            }

            settingsSection("Sensors") {
                settingsRow(title: "Motion Right Stick", detail: "Maps the selected motion source to the virtual controller right stick.") {
                    Toggle("", isOn: $manager.motionRightStickEnabled)
                        .labelsHidden()
                        .disabled(!manager.virtualGamepadEnabled)
                }
                rowDivider()
                settingsRow(title: "Motion Input Source", detail: manager.motionInputSource.detail) {
                    Picker("Motion Input Source", selection: $manager.motionInputSource) {
                        ForEach(MotionInputSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                    .disabled(!manager.virtualGamepadEnabled || !manager.motionRightStickEnabled)
                }
                rowDivider()
                settingsRow(title: "Read MotionPlus Gyro", detail: "Activates MotionPlus or Wii Remote Plus gyroscope axes for motion input without a sensor bar.") {
                    Toggle("", isOn: $manager.motionPlusEnabled)
                        .labelsHidden()
                }
                rowDivider()
                settingsRow(title: "Read IR Points", detail: "Initializes the Wii Remote IR camera. Wii protocol IR report modes also carry accelerometer bytes; virtual motion mapping remains controlled separately.") {
                    Toggle("", isOn: $manager.irCameraEnabled)
                        .labelsHidden()
                }
            }

            settingsSection("Runtime Environment") {
                environmentRow(
                    title: "Virtual HID Entitlement",
                    value: developerLabEnvironment.entitlementSummary,
                    symbolName: developerLabEnvironment.virtualHIDEntitlementVisible ? "checkmark.circle.fill" : "lock.circle.fill",
                    color: developerLabEnvironment.virtualHIDEntitlementVisible ? .green : .secondary
                )
                rowDivider()
                environmentRow(
                    title: "Signing",
                    value: developerLabEnvironment.signingSummary,
                    symbolName: "signature",
                    color: .secondary
                )
                rowDivider()
                environmentRow(
                    title: "AMFI Hint",
                    value: developerLabEnvironment.amfiSummary,
                    symbolName: developerLabEnvironment.amfiRelaxationHintDetected ? "exclamationmark.triangle.fill" : "shield.fill",
                    color: developerLabEnvironment.amfiRelaxationHintDetected ? .orange : .secondary
                )
            }

            settingsSection("Related Settings") {
                settingsRow(title: "Accessibility", detail: "Some target apps may request Accessibility permission separately from virtual HID publication.") {
                    Button("Open") { manager.openAccessibilitySettings() }
                }
            }
        }
    }

    private var bluetoothPage: some View {
        settingsPage(title: "Bluetooth", subtitle: "Discovery, pairing, and macOS Bluetooth state.") {
            settingsSection("Status") {
                settingsRow(title: "Bluetooth", detail: bluetoothDetail) {
                    Label(manager.phase.title, systemImage: statusSymbol)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(statusColor)
                }
            }

            settingsSection("Pairing") {
                instructionRow(
                    title: "Use red SYNC",
                    message: "Press the red SYNC button behind the battery cover. If macOS shows a Connection Request dialog after pressing another button, cancel it and WiiMacMote will continue scanning."
                )
                rowDivider()
                HStack(spacing: 8) {
                    scanToggleButton
                    Button("Open Bluetooth Settings") { manager.openBluetoothSettings() }
                    if case .permissionDenied = manager.phase {
                        Button("Open Privacy Settings") { manager.openBluetoothPrivacySettings() }
                    }
                    if case .error = manager.phase {
                        Button("Retry") { manager.retryNow() }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private var diagnosticsPage: some View {
        settingsPage(title: "Diagnostics", subtitle: "Recent Bluetooth, HID, and virtual-output events.") {
            settingsSection("DSU / Cemuhook") {
                settingsRow(title: "Controller UDP Stream", detail: "Publishes controller data for Dolphin, Cemu-compatible clients, and other DSU/Cemuhook consumers on localhost.") {
                    Toggle("", isOn: $manager.diagnosticsDSUEnabled)
                        .labelsHidden()
                }
                rowDivider()
                environmentRow(
                    title: "Endpoint",
                    value: manager.diagnosticsDSUStatusText,
                    symbolName: manager.diagnosticsDSUEnabled ? "network" : "network.slash",
                    color: manager.diagnosticsDSUEnabled ? .blue : .secondary
                )
                rowDivider()
                instructionRow(
                    title: "Client Setup",
                    message: "Configure DSU/Cemuhook clients to use UDP 127.0.0.1:26760. Rumble packets are forwarded to the matching Wii Remote slot."
                )
            }

            settingsSection("Log") {
                HStack {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(manager.diagnostics.plainText, forType: .string)
                    }
                    Button("Clear") { manager.diagnostics.clear() }
                    Spacer()
                    Text("\(manager.diagnostics.entries.count) entries")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                rowDivider()
                diagnosticLog
            }
        }
    }

    private var connectionSection: some View {
        settingsSection("Connection") {
            settingsRow(title: "Discovery", detail: bluetoothDetail) {
                HStack(spacing: 8) {
                    if manager.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    scanToggleButton
                    Button("Bluetooth Settings") { manager.openBluetoothSettings() }
                }
            }
        }
    }

    private var emptyControllerSection: some View {
        settingsSection {
            HStack(spacing: 22) {
                ControllerArtwork(kind: .remote, active: false)
                    .frame(width: 112, height: 180)
                    .padding(.leading, 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text("No Game Controllers")
                        .font(.title3.weight(.semibold))
                    Text("Turn on Scan, then press the red SYNC button behind the Wii Remote battery cover. Avoid normal buttons during pairing; macOS handles those as a system Bluetooth connection request.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        scanToggleButton
                        Button("Bluetooth Settings") { manager.openBluetoothSettings() }
                    }
                    .padding(.top, 4)
                }
                Spacer()
            }
            .padding(16)
        }
    }

    private func connectedControllerSection(_ wiimote: ConnectedWiimoteSnapshot) -> some View {
        settingsSection(wiimote.name.isEmpty ? "Wii Remote" : wiimote.name) {
            HStack(alignment: .center, spacing: 22) {
                ControllerArtwork(kind: artworkKind(for: wiimote), active: true)
                    .frame(width: 132, height: 190)
                    .padding(.leading, 4)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Player \(wiimote.playerIndex)")
                                .font(.title3.weight(.semibold))
                            Text(wiimote.address ?? String(format: "Product 0x%04X", wiimote.productID))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        batteryView(wiimote.batteryPercent)
                    }

                    HStack(spacing: 8) {
                        Button("Refresh") { manager.requestStatus(id: wiimote.id) }
                        Button("Identify") {
                            manager.setRumble(id: wiimote.id, enabled: true)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                manager.setRumble(id: wiimote.id, enabled: false)
                            }
                        }
                        if manager.motionRightStickEnabled {
                            Button("Center Motion") { manager.calibrateMotion(id: wiimote.id) }
                        }
                        Button("Disconnect") { manager.disconnectWiimote(id: wiimote.id) }
                    }
                }
            }
            .padding(16)

            rowDivider()
            controllerMetricRow("Buttons", wiimote.buttons.isEmpty ? "None" : wiimote.buttons.joined(separator: "  "))
            rowDivider()
            controllerMetricRow("Input Rate", "\(wiimote.reportsPerSecond) reports/s")
            rowDivider()
            controllerMetricRow("Last Report", wiimote.reportID.map { String(format: "0x%02X", $0) } ?? "None")
            rowDivider()
            controllerMetricRow("Motion", accelerationText(wiimote.acceleration))
            rowDivider()
            controllerMetricRow("Extension Motion", accelerationText(wiimote.extensionAcceleration))
            rowDivider()
            controllerMetricRow("Gyroscope", gyroscopeText(wiimote.motionPlusGyroscope))
            rowDivider()
            controllerMetricRow("Extension", extensionText(wiimote))
            rowDivider()
            controllerMetricRow("IR Points", irPointText(wiimote))
            rowDivider()
            controllerMetricRow("Virtual Output", virtualGamepadText(wiimote))

            if let error = wiimote.virtualGamepadError {
                rowDivider()
                environmentRow(
                    title: "Output Error",
                    value: error,
                    symbolName: "exclamationmark.triangle.fill",
                    color: .orange
                )
            }
        }
    }

    private func savedControllerRow(_ remote: SavedWiimoteSnapshot) -> some View {
        HStack(spacing: 12) {
            ControllerArtwork(kind: .remote, active: remote.isConnected)
                .frame(width: 42, height: 68)

            VStack(alignment: .leading, spacing: 3) {
                Text(remote.name)
                Text(remote.address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(remote.isConnected ? "Connected" : "Not Connected", systemImage: remote.isConnected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(remote.isConnected ? .green : .secondary)

            if remote.isConnected {
                Button("Disconnect") { manager.disconnectSavedWiimote(address: remote.address) }
            } else {
                Text("Turn on Scan to reconnect")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Forget", role: .destructive) {
                savedRemotePendingRemoval = remote
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var diagnosticLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(manager.diagnostics.entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: entry.symbolName)
                                .frame(width: 16)
                                .foregroundStyle(diagnosticColor(for: entry.level))
                            Text(entry.time, format: .dateTime.hour().minute().second())
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                            Text(entry.level)
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                            Text(entry.message)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption.monospaced())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .id(entry.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 260, maxHeight: 380)
            .onChange(of: manager.diagnostics.entries.count) { _, _ in
                guard let last = manager.diagnostics.entries.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func settingsPage<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.largeTitle.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content()
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .background(.background)
    }

    private func settingsSection<Content: View>(
        _ title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.headline)
                    .padding(.leading, 2)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28), lineWidth: 1)
            }
        }
    }

    private func settingsRow<Trailing: View>(
        title: String,
        detail: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func controllerMetricRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func environmentRow(title: String, value: String, symbolName: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func instructionRow(title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func emptyRow(title: String, message: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func rowDivider() -> some View {
        Divider()
            .padding(.leading, 12)
    }

    @ViewBuilder
    private var scanToggleButton: some View {
        if manager.automaticScanning {
            Button("Stop Scanning") {
                manager.automaticScanning = false
            }
            .buttonStyle(.bordered)
        } else {
            Button("Scan") {
                manager.automaticScanning = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.wiimotes.count >= 4)
        }
    }

    private var statusBadge: some View {
        Label(statusBadgeText, systemImage: statusSymbol)
            .font(.callout)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.10), in: Capsule())
    }

    private var controllerSubtitle: String {
        if manager.wiimotes.isEmpty {
            return manager.isScanning ? "Searching for Wii Remotes in red-SYNC mode." : "No connected Wii Remote."
        }
        return "Customize and monitor connected controllers."
    }

    private var bluetoothDetail: String {
        switch manager.phase {
        case .bluetoothOff:
            return "Turn Bluetooth on, then return here."
        case .permissionDenied:
            return "Allow WiiMacMote in Privacy & Security > Bluetooth."
        case .error:
            return "Review Diagnostics for the exact Bluetooth or HID result."
        case .scanning:
            return "Listening for red-SYNC pairing and saved controllers."
        case .pairing, .waitingForHID:
            return "Keep the controller nearby until a player light remains on."
        case .connected:
            return manager.isScanning ? "Connected and continuing discovery." : "Connected."
        case .starting:
            return "Starting Bluetooth services."
        case .idle:
            return "Ready to scan."
        }
    }

    private var statusBadgeText: String {
        if manager.isScanning { return "Scanning" }
        switch manager.phase {
        case .connected(let count): return "\(count) Connected"
        case .idle: return "Ready"
        case .bluetoothOff: return "Bluetooth Off"
        case .permissionDenied: return "Permission Needed"
        case .error: return "Needs Attention"
        case .starting: return "Starting"
        case .pairing: return "Pairing"
        case .waitingForHID: return "Connecting"
        case .scanning: return "Scanning"
        }
    }

    private var statusColor: Color {
        switch manager.phase {
        case .connected: return .green
        case .permissionDenied, .error: return .red
        case .bluetoothOff: return .orange
        case .starting, .scanning, .pairing, .waitingForHID: return .blue
        case .idle: return .secondary
        }
    }

    private var statusSymbol: String {
        switch manager.phase {
        case .connected: return "checkmark.circle.fill"
        case .permissionDenied: return "hand.raised.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .bluetoothOff: return "bolt.horizontal.circle.fill"
        case .scanning: return "dot.radiowaves.left.and.right"
        case .pairing, .waitingForHID: return "link.circle.fill"
        case .starting: return "gearshape.fill"
        case .idle: return "circle"
        }
    }

    private var developerLabEnvironment: DeveloperLabEnvironmentSnapshot {
        DeveloperLabEnvironment.snapshot()
    }

    private var savedRemoteRemovalIsPresented: Binding<Bool> {
        Binding(
            get: { savedRemotePendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    savedRemotePendingRemoval = nil
                }
            }
        )
    }

    private func batteryView(_ percent: Int?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: batterySymbol(percent))
            Text(percent.map { "\($0)%" } ?? "Reading")
                .monospacedDigit()
        }
        .foregroundStyle((percent ?? 100) < 20 ? .red : .secondary)
    }

    private func batterySymbol(_ percent: Int?) -> String {
        guard let percent else { return "battery.0percent" }
        switch percent {
        case 75...: return "battery.100percent"
        case 50..<75: return "battery.75percent"
        case 25..<50: return "battery.50percent"
        case 1..<25: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func accelerationText(_ acceleration: WiimoteAcceleration?) -> String {
        guard let acceleration else { return "Off" }
        return String(
            format: "x %+.2f g   y %+.2f g   z %+.2f g",
            acceleration.xG,
            acceleration.yG,
            acceleration.zG
        )
    }

    private func gyroscopeText(_ gyroscope: WiimoteMotionPlusGyroscope?) -> String {
        guard let gyroscope else { return manager.motionPlusEnabled ? "Waiting for MotionPlus" : "Off" }
        return String(
            format: "yaw %+.1f deg/s   roll %+.1f deg/s   pitch %+.1f deg/s",
            gyroscope.yawDegreesPerSecond,
            gyroscope.rollDegreesPerSecond,
            gyroscope.pitchDegreesPerSecond
        )
    }

    private func extensionText(_ wiimote: ConnectedWiimoteSnapshot) -> String {
        guard wiimote.extensionConnected else { return "Not detected" }
        var parts = [wiimote.extensionName ?? "Initializing"]
        if let detail = wiimote.extensionDetail, !detail.isEmpty {
            parts.append(detail)
        }
        if let kilograms = wiimote.balanceWeightKilograms {
            parts.append(String(format: "%.1f kg", kilograms))
        }
        return parts.joined(separator: " - ")
    }

    private func virtualGamepadText(_ wiimote: ConnectedWiimoteSnapshot) -> String {
        guard wiimote.virtualGamepadActive else { return "Off" }
        return [wiimote.virtualGamepadIdentity, wiimote.virtualGamepadBackend]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    private func irPointText(_ wiimote: ConnectedWiimoteSnapshot) -> String {
        guard manager.irCameraEnabled else { return "Disabled" }
        guard !wiimote.irPoints.isEmpty else { return "No visible points" }
        return wiimote.irPoints.enumerated()
            .map { index, point in
                let size = point.size.map { " s\($0)" } ?? ""
                return "P\(index + 1) \(point.x),\(point.y)\(size)"
            }
            .joined(separator: "  ")
    }

    private func artworkKind(for wiimote: ConnectedWiimoteSnapshot) -> ControllerArtwork.Kind {
        let name = (wiimote.extensionName ?? "").lowercased()
        if name.contains("balance") { return .balanceBoard }
        if name.contains("classic") { return .classicController }
        if name.contains("nunchuk") { return .nunchuk }
        return .remote
    }

    private func diagnosticColor(for level: String) -> Color {
        switch level {
        case "Error": return .red
        case "Warning": return .orange
        case "Success": return .green
        case "Discovery", "Pairing": return .blue
        default: return .secondary
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case controllers
    case savedControllers
    case output
    case bluetooth
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controllers: return "Game Controllers"
        case .savedControllers: return "Saved Controllers"
        case .output: return "Output"
        case .bluetooth: return "Bluetooth"
        case .diagnostics: return "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .controllers: return "gamecontroller"
        case .savedControllers: return "rectangle.stack"
        case .output: return "display.and.arrow.down"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .diagnostics: return "stethoscope"
        }
    }
}

private struct ControllerArtwork: View {
    enum Kind {
        case remote
        case nunchuk
        case classicController
        case balanceBoard
    }

    let kind: Kind
    let active: Bool

    var body: some View {
        ZStack {
            switch kind {
            case .remote:
                remoteArtwork
            case .nunchuk:
                nunchukArtwork
            case .classicController:
                classicControllerArtwork
            case .balanceBoard:
                balanceBoardArtwork
            }
        }
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
        .accessibilityHidden(true)
    }

    private var remoteArtwork: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let bodyWidth = width * 0.44
            let bodyHeight = height * 0.88
            let outline = active ? Color.accentColor : Color.secondary

            ZStack {
                RoundedRectangle(cornerRadius: bodyWidth * 0.18, style: .continuous)
                    .fill(outline.opacity(active ? 0.10 : 0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: bodyWidth * 0.18, style: .continuous)
                            .stroke(outline.opacity(active ? 0.80 : 0.55), lineWidth: 2)
                    }
                    .frame(width: bodyWidth, height: bodyHeight)
                    .position(x: width / 2, y: height / 2)

                Capsule()
                    .fill(outline.opacity(active ? 0.18 : 0.10))
                    .frame(width: bodyWidth * 0.32, height: bodyHeight * 0.035)
                    .position(x: width / 2, y: height * 0.17)
            }
        }
    }

    private var nunchukArtwork: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let outline = active ? Color.accentColor : Color.secondary
            ZStack {
                NunchukBodyShape()
                    .fill(outline.opacity(active ? 0.10 : 0.06))
                    .overlay {
                        NunchukBodyShape()
                            .stroke(outline.opacity(active ? 0.80 : 0.55), lineWidth: 2)
                    }
                    .frame(width: width * 0.56, height: height * 0.78)
                    .position(x: width * 0.48, y: height * 0.52)

                Path { path in
                    path.move(to: CGPoint(x: width * 0.48, y: height * 0.14))
                    path.addCurve(
                        to: CGPoint(x: width * 0.82, y: height * 0.02),
                        control1: CGPoint(x: width * 0.50, y: height * 0.05),
                        control2: CGPoint(x: width * 0.70, y: height * 0.05)
                    )
                }
                .stroke(outline.opacity(active ? 0.65 : 0.42), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    private var classicControllerArtwork: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let outline = active ? Color.accentColor : Color.secondary
            ZStack {
                ClassicControllerBodyShape()
                    .fill(outline.opacity(active ? 0.10 : 0.06))
                    .overlay {
                        ClassicControllerBodyShape().stroke(outline.opacity(active ? 0.80 : 0.55), lineWidth: 2)
                    }
                    .frame(width: width * 0.92, height: height * 0.52)
                    .position(x: width / 2, y: height * 0.50)
            }
        }
    }

    private var balanceBoardArtwork: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let outline = active ? Color.accentColor : Color.secondary
            ZStack {
                RoundedRectangle(cornerRadius: height * 0.14, style: .continuous)
                    .fill(outline.opacity(active ? 0.10 : 0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: height * 0.14, style: .continuous)
                            .stroke(outline.opacity(active ? 0.80 : 0.55), lineWidth: 2)
                    }
                    .frame(width: width * 0.92, height: height * 0.46)
                    .position(x: width / 2, y: height * 0.52)

                RoundedRectangle(cornerRadius: width * 0.04, style: .continuous)
                    .stroke(outline.opacity(active ? 0.28 : 0.18), lineWidth: 1)
                    .frame(width: width * 0.66, height: height * 0.18)
                    .position(x: width / 2, y: height * 0.52)
            }
        }
    }
}

private struct DPadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let thirdX = rect.width / 3
        let thirdY = rect.height / 3
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: rect.minX + thirdX, y: rect.minY, width: thirdX, height: rect.height),
            cornerSize: CGSize(width: thirdX * 0.25, height: thirdX * 0.25)
        )
        path.addRoundedRect(
            in: CGRect(x: rect.minX, y: rect.minY + thirdY, width: rect.width, height: thirdY),
            cornerSize: CGSize(width: thirdY * 0.25, height: thirdY * 0.25)
        )
        return path
    }
}

private struct NunchukBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX * 0.98, y: rect.minY + rect.height * 0.34),
            control1: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.02),
            control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.15)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX * 0.96, y: rect.minY + rect.height * 0.70),
            control2: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.34),
            control1: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.maxY),
            control2: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.minY + rect.height * 0.70)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.15),
            control2: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.02)
        )
        path.closeSubpath()
        return path
    }
}

private struct ClassicControllerBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.18))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.18),
            control1: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY),
            control2: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.96, y: rect.minY + rect.height * 0.18),
            control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.32)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.maxY * 0.97),
            control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.78),
            control2: CGPoint(x: rect.minX + rect.width * 0.88, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.maxY * 0.97),
            control1: CGPoint(x: rect.minX + rect.width * 0.63, y: rect.minY + rect.height * 0.88),
            control2: CGPoint(x: rect.minX + rect.width * 0.37, y: rect.minY + rect.height * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.78)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.18),
            control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.32),
            control2: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.minY + rect.height * 0.18)
        )
        path.closeSubpath()
        return path
    }
}

private struct BalanceBoardShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.08))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.minY + rect.height * 0.08),
            control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.22)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.08),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.22),
            control2: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.maxY - rect.height * 0.08)
        )
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.08))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.maxY - rect.height * 0.08),
            control2: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.22)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.08),
            control1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.22),
            control2: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.08)
        )
        path.closeSubpath()
        return path
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
