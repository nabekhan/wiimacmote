import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var manager = WiimoteManager()
    @State private var selectedSection: SettingsSection? = .controllers
    @State private var savedRemotePendingRemoval: SavedWiimoteSnapshot?

    private struct SavedExtensionDisplayRow: Identifiable, Equatable {
        let id: String
        let name: String
        let identifierHex: String
        let remoteName: String
        let remoteAddress: String
        let isConnected: Bool
        let lastSeen: Date
    }

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
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selectedSection ?? .controllers {
        case .controllers:
            controllersPage
        case .bluetooth:
            bluetoothPage
        }
    }

    private var controllersPage: some View {
        settingsPage(title: "Controllers", subtitle: controllerSubtitle) {
            activeControllersSection
            controllerListSection
            savedExtensionsSection
        }
    }

    private var bluetoothPage: some View {
        settingsPage(title: "Bluetooth", subtitle: "Discovery, pairing, and Bluetooth log.") {
            settingsSection("Pairing") {
                instructionRow(
                    title: "New and Saved Controllers",
                    message: "For a new Wii Remote, turn on Scan and press the red SYNC button behind the battery cover; if the LEDs stop blinking press a face button such as 1 or 2. For a saved Wii Remote, turn on Scan and press a face button. Connection can take a moment."
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

            settingsSection("Status") {
                settingsRow(title: "Bluetooth", detail: bluetoothDetail) {
                    Label(manager.phase.title, systemImage: statusSymbol)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(statusColor)
                }
            }

            bluetoothLogSection
        }
    }

    @ViewBuilder
    private var activeControllersSection: some View {
        if manager.wiimotes.isEmpty {
            emptyControllerSection
        } else {
            ForEach(manager.wiimotes) { wiimote in
                connectedControllerSection(wiimote)
            }
        }
    }

    private var emptyControllerSection: some View {
        settingsSection("Active Controllers") {
            HStack(spacing: 22) {
                ControllerArtwork(kind: .remote, active: false)
                    .frame(width: 112, height: 180)
                    .padding(.leading, 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text("No Active Controllers")
                        .font(.title3.weight(.semibold))
                    Text("Turn on Scan. For a new Wii Remote, press red SYNC behind the battery cover. For a saved Wii Remote, press a face button such as 1 or 2.")
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

    private var controllerListSection: some View {
        settingsSection("Saved Controllers") {
            if manager.savedWiimotes.isEmpty {
                emptyRow(
                    title: "No saved Wii controllers",
                    message: "Pair controllers from Bluetooth. Saved Wii Remotes and Wii Fit Balance Boards will appear here with active status.",
                    systemImage: "gamecontroller"
                )
            } else {
                ForEach(manager.savedWiimotes) { remote in
                    savedControllerRow(remote)
                    if remote.id != manager.savedWiimotes.last?.id {
                        rowDivider()
                    }
                }
            }
        }
    }

    private var bluetoothLogSection: some View {
        settingsSection("Log") {
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(manager.diagnostics.plainText, forType: .string)
                }
                Button("Clear") { manager.diagnostics.clear() }
                Spacer()
                Text("\(visibleBluetoothLogEntries.count) recent entries")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            rowDivider()
            bluetoothLog
        }
    }

    private func connectedControllerSection(_ wiimote: ConnectedWiimoteSnapshot) -> some View {
        settingsSection(wiimote.name.isEmpty ? "Active Controller" : wiimote.name) {
            HStack(alignment: .center, spacing: 22) {
                connectedControllerArtwork(wiimote)
                    .frame(width: 170, height: 190)
                    .padding(.leading, 4)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Player \(wiimote.playerIndex)")
                                .font(.title3.weight(.semibold))
                            Text(controllerTypeText(wiimote))
                                .font(.callout.weight(.medium))
                            Text(wiimote.address ?? String(format: "Product 0x%04X", wiimote.productID))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        batteryView(wiimote.batteryPercent)
                    }

                    HStack(spacing: 8) {
                        Button("Identify") { identify(wiimote) }
                        Button("Disconnect") { manager.disconnectWiimote(id: wiimote.id) }
                    }
                }
            }
            .padding(16)

            rowDivider()
            controllerMetricRow("Hardware", hardwareText(wiimote))
            rowDivider()
            controllerMetricRow("Extension", extensionText(wiimote))
            rowDivider()
            controllerMetricRow("Buttons Pressed", wiimote.buttons.isEmpty ? "None" : wiimote.buttons.joined(separator: "  "))
            rowDivider()
            controllerMetricRow("Input Rate", "\(wiimote.reportsPerSecond) reports/s")
            rowDivider()
            controllerMetricRow("Remote Type", wiimote.remoteKind.title)
            rowDivider()
            controllerMetricRow("MotionPlus", wiimote.motionPlusCapability.title)
        }
    }

    private func savedControllerRow(_ remote: SavedWiimoteSnapshot) -> some View {
        HStack(spacing: 12) {
            savedControllerArtwork(remote)
                .frame(width: 54, height: 68)

            VStack(alignment: .leading, spacing: 3) {
                Text(remote.name)
                    .font(.body.weight(.medium))
                Text(savedControllerTypeText(remote))
                    .font(.caption.weight(.medium))
                Text(remote.address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(remote.isConnected ? "Active" : "Saved", systemImage: remote.isConnected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(remote.isConnected ? .green : .secondary)

            Button("Forget", role: .destructive) {
                savedRemotePendingRemoval = remote
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var savedExtensionsSection: some View {
        let rows = savedExtensionRows
        if !rows.isEmpty {
            settingsSection("Saved Extensions") {
                ForEach(rows) { extensionRow in
                    savedExtensionRow(extensionRow)
                    if extensionRow.id != rows.last?.id {
                        rowDivider()
                    }
                }
            }
        }
    }

    private func savedExtensionRow(_ extensionRow: SavedExtensionDisplayRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.title3)
                .foregroundStyle(extensionRow.isConnected ? Color.accentColor : Color.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(extensionRow.name)
                    .font(.body.weight(.medium))
                Text(extensionRow.identifierHex)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text("Saved with \(extensionRow.remoteName) - \(extensionRow.remoteAddress)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if extensionRow.isConnected {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Button("Forget", role: .destructive) {
                manager.removeSavedExtension(
                    remoteAddress: extensionRow.remoteAddress,
                    identifierHex: extensionRow.identifierHex
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var bluetoothLog: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visibleBluetoothLogEntries.reversed()) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: entry.symbolName)
                            .frame(width: 16)
                            .foregroundStyle(logColor(for: entry.level))
                        Text(entry.time, format: .dateTime.hour().minute().second())
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        Text(entry.level)
                            .foregroundStyle(.secondary)
                            .frame(width: 76, alignment: .leading)
                        Text(entry.message)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.monospaced())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 240, maxHeight: 360)
    }

    private var visibleBluetoothLogEntries: [DiagnosticLog.Entry] {
        Array(manager.diagnostics.entries.suffix(80))
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

    private var savedExtensionRows: [SavedExtensionDisplayRow] {
        let activeExtensionIDs = Set(manager.wiimotes.compactMap { wiimote in
            wiimote.extensionIdentifierHex.map { "\(normalizedBluetoothAddress(wiimote.address ?? "")):\($0)" }
        })

        return manager.savedWiimotes
            .flatMap { remote in
                remote.extensions.map { extensionSnapshot in
                    let normalizedRemoteAddress = normalizedBluetoothAddress(remote.address)
                    return SavedExtensionDisplayRow(
                        id: extensionSnapshot.id,
                        name: extensionSnapshot.name,
                        identifierHex: extensionSnapshot.identifierHex,
                        remoteName: remote.name,
                        remoteAddress: remote.address,
                        isConnected: activeExtensionIDs.contains("\(normalizedRemoteAddress):\(extensionSnapshot.identifierHex)"),
                        lastSeen: extensionSnapshot.lastSeen
                    )
                }
            }
            .sorted {
                if $0.isConnected != $1.isConnected { return $0.isConnected }
                if $0.lastSeen != $1.lastSeen { return $0.lastSeen > $1.lastSeen }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private var controllerSubtitle: String {
        if manager.wiimotes.isEmpty {
            return manager.savedWiimotes.isEmpty ? "No saved or active controllers." : "Saved controllers and extensions."
        }
        return "\(manager.wiimotes.count) active controller\(manager.wiimotes.count == 1 ? "" : "s"), saved controllers, and saved extensions."
    }

    private var bluetoothDetail: String {
        switch manager.phase {
        case .bluetoothOff:
            return "Turn Bluetooth on, then return here."
        case .permissionDenied:
            return "Allow WiiMacMote in Privacy & Security > Bluetooth."
        case .error:
            return "Review the Bluetooth log for the exact Bluetooth or HID result."
        case .scanning:
            return "Listening for red SYNC and saved controller button presses."
        case .pairing, .waitingForHID:
            return "Connection can take a moment; wait for a player light to stay on."
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

    private func identify(_ wiimote: ConnectedWiimoteSnapshot) {
        manager.setRumble(id: wiimote.id, enabled: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            manager.setRumble(id: wiimote.id, enabled: false)
        }
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

    private func hardwareText(_ wiimote: ConnectedWiimoteSnapshot) -> String {
        var parts = [wiimote.remoteKind.title]
        if let address = wiimote.address, !address.isEmpty {
            parts.append(address)
        } else {
            parts.append(String(format: "Product 0x%04X", wiimote.productID))
        }
        return parts.joined(separator: " - ")
    }

    private func extensionText(_ wiimote: ConnectedWiimoteSnapshot) -> String {
        guard wiimote.extensionConnected else { return "Not detected" }
        var parts = [wiimote.extensionName ?? "Initializing"]
        if let identifier = wiimote.extensionIdentifierHex {
            parts.append(identifier)
        }
        if let detail = wiimote.extensionDetail, !detail.isEmpty {
            parts.append(detail)
        }
        if let kilograms = wiimote.balanceWeightKilograms {
            parts.append(String(format: "%.1f kg", kilograms))
        }
        return parts.joined(separator: " - ")
    }

    private func controllerTypeText(_ wiimote: ConnectedWiimoteSnapshot) -> String {
        if wiimote.remoteKind == .balanceBoard {
            return wiimote.remoteKind.title
        }

        var parts = [wiimote.remoteKind.title]
        if let extensionName = wiimote.extensionName,
           !extensionName.lowercased().contains("motionplus") {
            parts.append(extensionName)
        }
        if wiimote.motionPlusCapability.isKnownPresent,
           !parts.contains(where: { $0.lowercased().contains("motionplus") || $0.lowercased().contains("remote plus") }) {
            parts.append("MotionPlus")
        }
        return parts.joined(separator: " + ")
    }

    private func savedControllerTypeText(_ remote: SavedWiimoteSnapshot) -> String {
        if remote.motionPlusCapability.isKnownPresent,
           remote.remoteKind != .motionPlusInside,
           remote.remoteKind != .balanceBoard {
            return remote.remoteKind.title + " + MotionPlus"
        }
        return remote.remoteKind.title
    }

    @ViewBuilder
    private func connectedControllerArtwork(_ wiimote: ConnectedWiimoteSnapshot) -> some View {
        if wiimote.remoteKind == .balanceBoard || extensionArtworkKind(for: wiimote) == .balanceBoard {
            ControllerArtwork(kind: .balanceBoard, active: true)
        } else {
            HStack(alignment: .center, spacing: 4) {
                ControllerArtwork(kind: .remote, active: true)
                    .frame(width: 78, height: 170)
                if let extensionKind = extensionArtworkKind(for: wiimote) {
                    ControllerArtwork(kind: extensionKind, active: true)
                        .frame(width: 78, height: 150)
                }
            }
        }
    }

    @ViewBuilder
    private func savedControllerArtwork(_ remote: SavedWiimoteSnapshot) -> some View {
        if remote.remoteKind == .balanceBoard {
            ControllerArtwork(kind: .balanceBoard, active: remote.isConnected)
                .frame(width: 54, height: 42)
        } else {
            ControllerArtwork(kind: .remote, active: remote.isConnected)
                .frame(width: 42, height: 68)
        }
    }

    private func extensionArtworkKind(for wiimote: ConnectedWiimoteSnapshot) -> ControllerArtwork.Kind? {
        let name = (wiimote.extensionName ?? "").lowercased()
        if name.contains("balance") { return .balanceBoard }
        if name.contains("classic") { return .classicController }
        if name.contains("nunchuk") { return .nunchuk }
        return nil
    }

    private func normalizedBluetoothAddress(_ address: String) -> String {
        address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "-")
            .lowercased()
    }

    private func logColor(for level: String) -> Color {
        switch level {
        case "Error": return .red
        case "Warning": return .orange
        case "Success": return .green
        case "Discovery", "Pairing", "Connection": return .blue
        case "Removal": return .orange
        case "Extension": return .purple
        default: return .secondary
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case controllers
    case bluetooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controllers: return "Controllers"
        case .bluetooth: return "Bluetooth"
        }
    }

    var systemImage: String {
        switch self {
        case .controllers: return "gamecontroller"
        case .bluetooth: return "dot.radiowaves.left.and.right"
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
                BalanceBoardShape()
                    .fill(outline.opacity(active ? 0.10 : 0.06))
                    .overlay {
                        BalanceBoardShape()
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
