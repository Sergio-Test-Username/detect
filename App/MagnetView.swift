import SwiftUI
import CoreMotion
import UIKit

final class MagnetService: ObservableObject {
    private let manager = CMMotionManager()
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private var lastHaptic = Date.distantPast

    @Published var magnitude: Double = 0
    @Published var baseline: Double = 0
    @Published var delta: Double = 0
    @Published var peak: Double = 0
    @Published var history: [Double] = []
    @Published var running = false
    @Published var available = true
    private(set) var sampleCount = 0

    static let historyLimit = 100
    static let warmup = 40

    func start() {
        guard manager.isMagnetometerAvailable else {
            available = false
            return
        }
        reset()
        haptic.prepare()
        manager.magnetometerUpdateInterval = 0.05
        running = true
        manager.startMagnetometerUpdates(to: OperationQueue.main) { [weak self] (data: CMMagnetometerData?, _: Error?) in
            guard let self = self, let field = data?.magneticField else { return }
            let m: Double = (field.x * field.x + field.y * field.y + field.z * field.z).squareRoot()
            self.handle(m)
        }
    }

    func stop() {
        manager.stopMagnetometerUpdates()
        running = false
    }

    func reset() {
        sampleCount = 0
        magnitude = 0
        baseline = 0
        delta = 0
        peak = 0
        history = []
    }

    func recalibrate() {
        sampleCount = 0
        peak = 0
        delta = 0
    }

    private func handle(_ m: Double) {
        sampleCount += 1
        magnitude = m
        if sampleCount == 1 {
            baseline = m
        } else if sampleCount < MagnetService.warmup {
            baseline += (m - baseline) * 0.15
        } else if abs(m - baseline) < 12 {
            baseline += (m - baseline) * 0.01
        }
        let d: Double = abs(m - baseline)
        delta = sampleCount < MagnetService.warmup ? 0 : d
        history.append(delta)
        if history.count > MagnetService.historyLimit {
            history.removeFirst(history.count - MagnetService.historyLimit)
        }
        if sampleCount >= MagnetService.warmup {
            peak = max(peak, d)
            if d > 20 && Date().timeIntervalSince(lastHaptic) > 0.15 {
                lastHaptic = Date()
                haptic.impactOccurred(intensity: CGFloat(min(1.0, d / 80.0)))
            }
        }
    }
}

struct SparkLine: View {
    let values: [Double]
    let maxValue: Double

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard values.count > 1 else { return }
                let stepX: CGFloat = geo.size.width / CGFloat(MagnetService.historyLimit - 1)
                for (i, v) in values.enumerated() {
                    let x: CGFloat = CGFloat(i) * stepX
                    let ratio: CGFloat = CGFloat(min(v, maxValue) / maxValue)
                    let y: CGFloat = geo.size.height * (1 - ratio)
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Theme.primaryGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

struct MagnetView: View {
    @EnvironmentObject var store: ScanStore
    @StateObject private var magnet = MagnetService()

    private var levelRisk: Risk {
        if magnet.delta >= 40 { return .danger }
        if magnet.delta >= 15 { return .caution }
        return .clear
    }

    private var levelText: String {
        if !magnet.running { return "Idle" }
        if magnet.sampleCount < MagnetService.warmup { return "Calibrating" }
        if magnet.delta >= 40 { return "Strong field" }
        if magnet.delta >= 15 { return "Elevated" }
        return "Normal"
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    InfoCard(
                        symbol: "waveform.path.ecg",
                        title: "Find hidden electronics",
                        text: "Cameras, transmitters and batteries create small magnetic fields. Hold the top edge of your phone near suspicious objects and watch for spikes."
                    )
                    if magnet.available {
                        readingCard
                        chartCard
                        controls
                    } else {
                        unavailableCard
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Magnetic Scan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            finish()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var readingCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(magnet.delta.rounded()))")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("µT above baseline")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(levelRisk.color)
                        .frame(width: max(8, geo.size.width * CGFloat(min(magnet.delta / 80.0, 1.0))))
                }
            }
            .frame(height: 12)
            HStack {
                StatusChip(risk: levelRisk, text: levelText)
                Spacer()
                Text("Field \(Int(magnet.magnitude.rounded())) · Peak \(Int(magnet.peak.rounded())) µT")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .animation(.spring(duration: 0.3), value: levelRisk)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live signal")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            SparkLine(values: magnet.history, maxValue: 80)
                .frame(height: 110)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                if magnet.running {
                    finish()
                } else {
                    magnet.start()
                }
            } label: {
                Label(magnet.running ? "Stop scan" : "Start scan", systemImage: magnet.running ? "stop.fill" : "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(colors: magnet.running ? [Theme.danger, Color(red: 0.75, green: 0.18, blue: 0.3)] : [Theme.accent, Theme.accentDeep]))

            if magnet.running {
                Button {
                    magnet.recalibrate()
                } label: {
                    Label("Recalibrate here", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Text("Move away from speakers, laptops and metal tables first, then press Recalibrate. Large magnets and appliances also cause spikes, so check the spot by eye.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var unavailableCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.warn)
            Text("Magnetometer unavailable")
                .font(.system(.headline, design: .rounded))
            Text("This device doesn't report magnetic field data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func finish() {
        guard magnet.running else { return }
        magnet.stop()
        guard magnet.sampleCount >= 100 else { return }
        let p: Int = Int(magnet.peak.rounded())
        if magnet.peak >= 30 {
            store.report(.magnetic, .caution, "Spike of \(p) µT found. Check that spot.")
        } else {
            store.report(.magnetic, .clear, "No magnetic anomalies (peak \(p) µT)")
        }
    }
}
