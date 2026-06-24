import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var manager = WiimoteManager()
    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if WiiMacMoteBuildFlavor.isDeveloperLab {
                        developerLabBanner
                    }

                    statusCard

                    if manager.wiimotes.isEmpty {
                        pairingGuide
                    } else {
                        ForEach(manager.wiimotes) { wiimote in
                            wiimoteCard(wiimote)
                        }
                    }

                    outputSettings

                    if showDiagnostics {
                        diagnosticsCard
                    }
                }
                .padding(18)
            }

            Divider()
            actionBar
        }
        .frame(minWidth: 720, minHeight: 760)
        .onAppear { manager.start() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 46, height: 46)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(headerColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("WiiMacMote")
                    .font(.title2.weight(.semibold))
                Text("Modern Wii Remote bridge for macOS · \(WiiMacMoteBuildFlavor.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !manager.wiimotes.isEmpty {
                Label(
                    "\(manager.wiimotes.count) connected",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }

    private var developerLabEnvironment: DeveloperLabEnvironmentSnapshot {
        DeveloperLabEnvironment.snapshot()
    }

    private var developerLabBanner: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hammer.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Local ad-hoc virtual-HID lab")
                        .font(.headline)
                    Text("This build is for developers testing on a deliberately SIP/AMFI-relaxed Mac. It uses an ad-hoc signature and does not depend on an Apple team, provisioning profile, or WaveBird's approved signature. WiiMacMote never changes system security settings itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(
                        developerLabEnvironment.entitlementSummary,
                        systemImage: developerLabEnvironment.virtualHIDEntitlementVisible
                            ? "checkmark.seal.fill"
                            : "xmark.seal.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        developerLabEnvironment.virtualHIDEntitlementVisible ? .green : .red
                    )

                    Label(
                        developerLabEnvironment.signingSummary,
                        systemImage: developerLabEnvironment.teamIdentifier == nil
                            ? "signature"
                            : "person.badge.key.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Label(
                        developerLabEnvironment.amfiSummary,
                        systemImage: developerLabEnvironment.amfiRelaxationHintDetected
                            ? "exclamationmark.shield.fill"
                            : "shield.lefthalf.filled"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        developerLabEnvironment.amfiRelaxationHintDetected ? .orange : .secondary
                    )
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusCard: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 11, height: 11)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 5) {
                    Text(manager.phase.title)
                        .font(.headline)
                    Text(statusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if manager.phase.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusDetail: String {
        switch manager.phase {
        case .permissionDenied:
            return "Allow WiiMacMote under System Settings › Privacy & Security › Bluetooth."
        case .bluetoothOff:
            return "Turn Bluetooth on, then return here. Discovery resumes automatically."
        case .error:
            return "The diagnostic log contains the exact IOKit result. Pairing retries are intentionally bounded."
        case .connected:
            return manager.isScanning
                ? "Connected and continuing to scan for up to four remotes."
                : "Input is being processed on a dedicated HID queue."
        default:
            return "For RVL-CNT-01-TR remotes, use the red SYNC button rather than holding 1 + 2."
        }
    }

    private var pairingGuide: some View {
        GroupBox("Connect a Wii Remote") {
            VStack(alignment: .leading, spacing: 12) {
                guideRow(number: 1, text: "Turn on Bluetooth and grant the app Bluetooth permission.")
                guideRow(number: 2, text: "Open the battery cover and press the red SYNC button once.")
                guideRow(number: 3, text: "Keep the remote close to the Mac until its player LED stays lit.")

                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("Already-paired remotes are opened directly instead of being forced through the binary-PIN process again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private func guideRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.blue, in: Circle())
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func wiimoteCard(_ wiimote: ConnectedWiimoteSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("P\(wiimote.playerIndex)")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(playerColor(wiimote.playerIndex), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(wiimote.name)
                            .font(.headline)
                        Text(String(format: "Nintendo HID · PID 0x%04X", wiimote.productID))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    batteryView(wiimote.batteryPercent)
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 8) {
                    GridRow {
                        metricLabel("Buttons")
                        Text(wiimote.buttons.isEmpty ? "None" : wiimote.buttons.joined(separator: "  "))
                            .font(.callout.monospaced())
                    }
                    GridRow {
                        metricLabel("Input rate")
                        Text("\(wiimote.reportsPerSecond) reports/s")
                            .font(.callout.monospacedDigit())
                    }
                    GridRow {
                        metricLabel("Last report")
                        Text(wiimote.reportID.map { String(format: "0x%02X", $0) } ?? "—")
                            .font(.callout.monospaced())
                    }
                    GridRow {
                        metricLabel("Motion")
                        Text(accelerationText(wiimote.acceleration))
                            .font(.callout.monospacedDigit())
                    }
                    GridRow {
                        metricLabel("Extension")
                        Text(wiimote.extensionConnected ? "Detected (raw data only)" : "Not detected")
                            .font(.callout)
                    }
                    GridRow {
                        metricLabel("Virtual HID")
                        HStack(spacing: 5) {
                            Image(systemName: wiimote.virtualGamepadActive ? "checkmark.circle.fill" : "minus.circle")
                            Text(virtualGamepadText(wiimote))
                        }
                        .foregroundStyle(wiimote.virtualGamepadActive ? .green : .secondary)
                    }
                }

                if let error = wiimote.virtualGamepadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Button("Refresh Status") {
                        manager.requestStatus(id: wiimote.id)
                    }

                    Button("Rumble") {
                        manager.setRumble(id: wiimote.id, enabled: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            manager.setRumble(id: wiimote.id, enabled: false)
                        }
                    }

                    if manager.motionRightStickEnabled {
                        Button("Center Motion") {
                            manager.calibrateMotion(id: wiimote.id)
                        }
                    }

                    Spacer()
                }
                .controlSize(.small)
            }
            .padding(.top, 3)
        }
    }

    private func virtualGamepadText(_ wiimote: ConnectedWiimoteSnapshot) -> String {
        guard wiimote.virtualGamepadActive else { return "Off" }
        return [wiimote.virtualGamepadIdentity, wiimote.virtualGamepadBackend]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func metricLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 90, alignment: .leading)
    }

    private func batteryView(_ percent: Int?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: batterySymbol(percent))
            Text(percent.map { "\($0)%" } ?? "Reading…")
                .monospacedDigit()
        }
        .font(.callout)
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

    private var outputSettings: some View {
        GroupBox("Input & Output") {
            VStack(alignment: .leading, spacing: 13) {
                Toggle("Create an experimental virtual HID gamepad", isOn: $manager.virtualGamepadEnabled)

                if !WiiMacMoteBuildFlavor.isDeveloperLab {
                    Label(
                        "The Standard scheme intentionally omits Apple's restricted virtual-HID entitlement. Use the WiiMacMote Developer Lab scheme and its explicit ad-hoc signing script for local virtual-device testing.",
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Controller identity", selection: $manager.virtualGamepadIdentity) {
                    ForEach(VirtualGamepadIdentity.allCases) { identity in
                        Text(identity.title + (identity.isRecommended ? " · recommended" : ""))
                            .tag(identity)
                    }
                }
                .disabled(!manager.virtualGamepadEnabled)

                Text(manager.virtualGamepadIdentity.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if manager.virtualGamepadIdentity.isHardwareImpersonation {
                    Label(
                        "Compatibility profile: this publishes another vendor's VID/PID for research. Recognition is not guaranteed, and no real Bluetooth transport is created.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Publication backend", selection: $manager.virtualGamepadBackendPreference) {
                    ForEach(VirtualGamepadBackendPreference.allCases) { backend in
                        Text(backend.title).tag(backend)
                    }
                }
                .disabled(!manager.virtualGamepadEnabled)

                Text(manager.virtualGamepadBackendPreference.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Picker("Button profile", selection: $manager.controllerProfile) {
                    ForEach(ControllerProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .disabled(!manager.virtualGamepadEnabled)

                Text(manager.controllerProfile.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Map accelerometer tilt to the right stick", isOn: $manager.motionRightStickEnabled)
                    .disabled(!manager.virtualGamepadEnabled)

                HStack {
                    Toggle("Continue scanning for additional remotes", isOn: $manager.automaticScanning)
                    Spacer()
                    Button("Open Accessibility Settings") {
                        manager.openAccessibilitySettings()
                    }
                    .help("Some target applications may request Accessibility access. The virtual-HID entitlement is separate.")
                }
            }
            .padding(.top, 4)
        }
    }

    private var diagnosticsCard: some View {
        GroupBox {
            VStack(spacing: 0) {
                HStack {
                    Label("Diagnostic Log", systemImage: "text.alignleft")
                        .font(.headline)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(manager.diagnostics.plainText, forType: .string)
                    }
                    Button("Clear") { manager.diagnostics.clear() }
                }
                .padding(.bottom, 8)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(manager.diagnostics.entries) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(entry.icon)
                                    Text(entry.time, format: .dateTime.hour().minute().second())
                                        .foregroundStyle(.secondary)
                                    Text(entry.message)
                                        .textSelection(.enabled)
                                }
                                .font(.caption.monospaced())
                                .id(entry.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                    .frame(minHeight: 180, maxHeight: 280)
                    .onChange(of: manager.diagnostics.entries.count) { _, _ in
                        guard let last = manager.diagnostics.entries.last else { return }
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        HStack {
            switch manager.phase {
            case .permissionDenied:
                Button("Open Bluetooth Privacy") { manager.openBluetoothPrivacySettings() }
                    .buttonStyle(.borderedProminent)
            case .bluetoothOff:
                Button("Open Bluetooth Settings") { manager.openBluetoothSettings() }
                    .buttonStyle(.borderedProminent)
            case .error:
                Button("Retry") { manager.retryNow() }
                    .buttonStyle(.borderedProminent)
            default:
                if manager.isScanning {
                    Button("Stop Scanning") { manager.stopScanning() }
                } else if manager.wiimotes.count < 4 {
                    Button("Scan") { manager.startScanning() }
                        .buttonStyle(.borderedProminent)
                }
            }

            Spacer()

            Button {
                showDiagnostics.toggle()
            } label: {
                Label(
                    showDiagnostics ? "Hide Diagnostics" : "Show Diagnostics",
                    systemImage: "stethoscope"
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var statusColor: Color {
        switch manager.phase {
        case .connected: return .green
        case .error, .permissionDenied: return .red
        case .bluetoothOff: return .orange
        case .starting, .scanning, .pairing, .waitingForHID: return .blue
        case .idle: return .secondary
        }
    }

    private var headerColor: Color {
        manager.wiimotes.isEmpty ? .secondary : .green
    }

    private func playerColor(_ player: Int) -> Color {
        switch player {
        case 1: return .blue
        case 2: return .red
        case 3: return .green
        default: return .orange
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
