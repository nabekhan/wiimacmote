//
//  ContentView.swift
//  wiimacmote
//
//  Main UI — Continuous scanning and auto-pairing.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var wiimote = WiimoteManager()
    @State private var showLog = true

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()

            if !wiimote.connectedWiimotes.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        statusSection
                        batterySection
                        
                        if wiimote.state.isWorking {
                            if showLog {
                                diagnosticLogSection
                            }
                        }
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 0) {
                    statusSection.padding([.horizontal, .top])

                    if showLog {
                        diagnosticLogSection
                    } else {
                        instructionsSection.padding()
                    }
                }
            }

            Divider()
            actionBar
        }
        .frame(minWidth: 520, minHeight: 600)
        .onAppear {
            wiimote.startScanning()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 32))
                .foregroundStyle(wiimote.state == .connected ? .green : .secondary)

            VStack(alignment: .leading) {
                Text("WiiMacMote")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Auto-Pairing & Continuous Scanning")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            
            let activeCount = wiimote.connectedWiimotes.filter { $0.gamepadActive }.count
            if activeCount > 0 {
                Label("\(activeCount) Gamepad\(activeCount > 1 ? "s" : "") Active", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 10, height: 10)
                Text(wiimote.state.description)
                    .font(.headline)
                Spacer()
                if wiimote.state.isWorking {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            if case .error(let msg) = wiimote.state {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }

    private var stateColor: Color {
        switch wiimote.state {
        case .connected, .paired: return .green
        case .error: return .red
        case .scanning, .pairing, .connecting: return .orange
        case .devicesFound: return .blue
        default: return .gray
        }
    }

    // Controller visualization removed

    // MARK: - Battery
    private var batterySection: some View {
        VStack(spacing: 12) {
            ForEach(wiimote.connectedWiimotes) { device in
                HStack(spacing: 16) {
                    Text("P\(device.playerIndex)")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.blue)
                        .clipShape(Circle())
                    
                    if device.batteryLevel >= 0 {
                        Image(systemName: batteryIcon(for: device.batteryLevel))
                            .foregroundStyle(device.batteryLevel < 20 ? .red : .green)
                        Text("\(device.batteryLevel)%")
                            .font(.subheadline)
                    } else {
                        Text("Reading battery...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Rumble") {
                        wiimote.setRumble(playerIndex: device.playerIndex, on: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            wiimote.setRumble(playerIndex: device.playerIndex, on: false)
                        }
                    }
                    .controlSize(.small)
                    
                    Button("Disconnect") {
                        wiimote.disconnect(playerIndex: device.playerIndex)
                    }
                    .controlSize(.small)
                    .tint(.red)
                }
                .padding()
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(10)
            }
        }
    }

    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 75...100: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        case 1..<25: return "battery.25"
        default: return "battery.0"
        }
    }

    // MARK: - Diagnostic Log

    private var diagnosticLogSection: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Diagnostic Log", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                Button(action: { wiimote.log.clear() }) {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                Button(action: { showLog = false }) {
                    Label("Instructions", systemImage: "questionmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(wiimote.log.entries) { entry in
                            HStack(alignment: .top, spacing: 4) {
                                Text(entry.icon)
                                    .font(.system(size: 11))
                                Text(entry.time, format: .dateTime.hour().minute().second())
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(
                                        entry.icon == "❌" ? .red :
                                        entry.icon == "⚠️" ? .orange :
                                        entry.icon == "💡" ? .blue : .primary
                                    )
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: wiimote.log.entries.count) { _ in
                    if let last = wiimote.log.entries.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .background(Color.black.opacity(0.03))
        }
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to connect")
                .font(.headline)

            instructionRow(1, "App is scanning for Wiimotes...")
            instructionRow(2, "Press red SYNC button on Wiimote")
            instructionRow(3, "App will auto-detect and pair")
            instructionRow(4, "Wait for connection to complete")

            Divider()

            Text("Uses **Native macOS Bluetooth** with Private APIs")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Mapping: D-pad→Axes, A/B→A/B, 1→X, 2→Y, +→Start, -→Select")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Button(action: { showLog = true }) {
                Label("Show Diagnostic Log", systemImage: "text.alignleft")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(10)
    }

    private func instructionRow(_ num: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(num).")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.blue)
                .frame(width: 18, alignment: .trailing)
            Text(text)
                .font(.caption)
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: { wiimote.startScanning() }) {
                Label("Scan", systemImage: "antenna.radiowaves.left.and.right")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(wiimote.state.isWorking || wiimote.connectedWiimotes.count >= 4)

            if wiimote.state.isWorking {
                Button("Stop") { wiimote.stop() }
                    .controlSize(.large)
                
                // Add Cancel button if specific target is focused (implied by pairing state)
                if case .pairing = wiimote.state {
                    Button("Cancel") { wiimote.resetTarget() }
                        .controlSize(.large)
                        .tint(.red)
                }
            }
            
            if !wiimote.connectedWiimotes.isEmpty {
                Button("Disconnect All") {
                    wiimote.disconnectAll()
                }
                .controlSize(.large)
                .tint(.red)
            }
            
            // Add Restart Bluetooth button
            Button(action: { wiimote.killBluetoothd() }) {
                Label("Restart Bluetooth", systemImage: "exclamationmark.triangle")
            }
            .controlSize(.large)
            .tint(.orange)
            .help("Restarts bluetoothd (Requires Admin Password)")

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

#Preview {
    ContentView()
}
