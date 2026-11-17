import SwiftUI
import CoreBluetooth
import UIKit

struct BluetoothView: View {
    @EnvironmentObject var store: ScanStore
    @StateObject private var scanner = BluetoothScanner()
    @State private var started = false

    private var flaggedCount: Int {
        scanner.devices.filter { $0.flagged }.count
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    InfoCard(
                        symbol: "dot.radiowaves.left.and.right",
                        title: "Find camera transmitters",
                        text: "Many hidden cameras advertise over Bluetooth during setup. Walk around the room and watch for camera-like names and strong signals."
                    )
                    stateCard
                    summaryCard
                    deviceList
                    controls
                }
                .padding(16)
            }
        }
        .navigationTitle("Bluetooth")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            finish()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sensoryFeedback(trigger: flaggedCount) { (old: Int, new: Int) -> SensoryFeedback? in
            if new > old {
                return .warning
            }
            return nil
        }
    }

    @ViewBuilder
    private var stateCard: some View {
        if started && scanner.state == .unauthorized {
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.warn)
                Text("Bluetooth access is off")
                    .font(.system(.headline, design: .rounded))
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .cardStyle()
        } else if started && scanner.state == .poweredOff {
            HStack(spacing: 12) {
                Image(systemName: "bolt.slash.fill")
                    .foregroundStyle(Theme.warn)
                Text("Turn on Bluetooth to scan.")
                    .font(.subheadline)
                Spacer(minLength: 0)
            }
            .cardStyle()
        }
    }

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(scanner.devices.count)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("devices nearby")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                StatusChip(
                    risk: flaggedCount > 0 ? .caution : (scanner.isScanning ? .clear : .unknown),
                    text: flaggedCount > 0 ? "\(flaggedCount) suspicious" : (scanner.isScanning ? "Listening" : "Idle")
                )
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var deviceList: some View {
        if scanner.devices.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
                Text(scanner.isScanning ? "Listening for devices…" : "Start a scan to list nearby devices")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else {
            VStack(spacing: 10) {
                ForEach(scanner.devices.prefix(40)) { (device: BLEDevice) in
                    BLERow(device: device)
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                if scanner.isScanning {
                    finish()
                } else {
                    started = true
                    scanner.start()
                }
            } label: {
                Label(scanner.isScanning ? "Stop scan" : "Start scan", systemImage: scanner.isScanning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(colors: scanner.isScanning ? [Theme.danger, Color(red: 0.75, green: 0.18, blue: 0.3)] : [Theme.accent, Theme.accentDeep]))
            Text("Scan for at least 10 seconds while walking the room. Camera names are only a hint. Many hidden cameras don't use Bluetooth at all.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func finish() {
        guard scanner.isScanning else { return }
        scanner.stop()
        guard scanner.lastDuration >= 10 else { return }
        let flagged: [BLEDevice] = scanner.devices.filter { $0.flagged }
        let close: Bool = flagged.contains(where: { $0.rssi > -60 })
        if close {
            store.report(.bluetooth, .danger, "Camera-like device very close: \(flagged[0].name)")
        } else if !flagged.isEmpty {
            store.report(.bluetooth, .caution, "\(flagged.count) camera-like device name(s) nearby")
        } else {
            store.report(.bluetooth, .clear, "No camera-like devices among \(scanner.devices.count)")
        }
    }
}

struct BLERow: View {
    let device: BLEDevice

    private var bars: Int {
        if device.rssi > -55 { return 4 }
        if device.rssi > -67 { return 3 }
        if device.rssi > -80 { return 2 }
        return 1
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.flagged ? "video.fill" : "dot.radiowaves.left.and.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(device.flagged ? Theme.warn : Theme.accent)
                .frame(width: 40, height: 40)
                .background((device.flagged ? Theme.warn : Theme.accent).opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(device.hasName ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Text(device.maker.map { "\($0) · \(device.proximity)" } ?? device.proximity)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(1..<5) { (level: Int) in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(level <= bars ? Theme.accent : Color.primary.opacity(0.15))
                            .frame(width: 4, height: CGFloat(4 + level * 4))
                    }
                }
                Text("\(device.rssi) dBm")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(device.flagged ? Theme.warn.opacity(0.6) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
