import SwiftUI

struct NetworkView: View {
    @EnvironmentObject var store: ScanStore
    @StateObject private var scanner = NetworkScanner()

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    InfoCard(
                        symbol: "wifi",
                        title: "Scan the Wi-Fi network",
                        text: "Wireless cameras join the same Wi-Fi as you. This checks every address for camera streaming ports and camera web pages. Join the room's Wi-Fi first."
                    )
                    progressCard
                    if let message = scanner.error {
                        messageCard(symbol: "wifi.slash", text: message)
                    }
                    resultsSection
                    controls
                    Text("Allow Local Network access when prompted, then scan again if needed. Cameras on a different network, or with no open ports, can't be seen this way.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
        .navigationTitle("Wi-Fi Scan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            scanner.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scanner.finished) { (_: Bool, done: Bool) in
            if done { report() }
        }
        .sensoryFeedback(.success, trigger: scanner.finished)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(scanner.isScanning ? "Scanning \(scanner.localIP ?? "")" : (scanner.finished ? "Scan complete" : "Ready"))
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Text("\(Int(scanner.progress * 100))%")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            ProgressView(value: scanner.progress)
                .tint(Theme.accent)
            Text("\(scanner.devices.count) device(s) with open services")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func messageCard(symbol: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.warn)
            Text(text)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var resultsSection: some View {
        if scanner.devices.isEmpty {
            if scanner.finished {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.safe)
                    Text("No camera services found")
                        .font(.system(.headline, design: .rounded))
                    Text("No device on this network exposed a camera or streaming port.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .cardStyle()
            }
        } else {
            VStack(spacing: 12) {
                ForEach(scanner.devices) { (device: NetDevice) in
                    DeviceRow(device: device)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private var controls: some View {
        Button {
            if scanner.isScanning {
                scanner.stop()
            } else {
                scanner.start()
            }
        } label: {
            Label(scanner.isScanning ? "Stop scan" : "Scan network", systemImage: scanner.isScanning ? "stop.fill" : "play.fill")
        }
        .buttonStyle(PrimaryButtonStyle(colors: scanner.isScanning ? [Theme.danger, Color(red: 0.75, green: 0.18, blue: 0.3)] : [Theme.accent, Theme.accentDeep]))
    }

    private func report() {
        let danger: Int = scanner.devices.filter { $0.risk == .danger }.count
        let caution: Int = scanner.devices.filter { $0.risk == .caution }.count
        if danger > 0 {
            store.report(.network, .danger, "\(danger) likely camera device(s) on this network")
        } else if caution > 0 {
            store.report(.network, .caution, "\(caution) unknown service(s) to identify")
        } else {
            store.report(.network, .clear, "No camera services among \(scanner.devices.count) device(s)")
        }
    }
}

struct DeviceRow: View {
    let device: NetDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(device.title)
                    .font(.system(.headline, design: .rounded))
                Spacer()
                StatusChip(risk: device.risk)
            }
            Text(device.ip)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Theme.accent)
            Text(device.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(device.ports, id: \.self) { (port: UInt16) in
                    Text(String(port))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                if !device.server.isEmpty {
                    Text(device.server)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
