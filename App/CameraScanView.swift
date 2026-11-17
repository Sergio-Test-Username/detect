import SwiftUI
import UIKit

struct HotspotMarker: View {
    let strength: CGFloat
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.danger, lineWidth: 3)
                .frame(width: 40, height: 40)
                .scaleEffect(pulse ? 1.25 : 0.9)
                .opacity(pulse ? 0.5 : 1)
            Circle()
                .fill(Theme.danger)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct CameraScanView: View {
    let mode: CameraMode
    @EnvironmentObject var store: ScanStore
    @StateObject private var camera = CameraService()
    @State private var running = false

    private var tool: Tool {
        mode == .lens ? .lens : .infrared
    }

    private var introText: String {
        if mode == .lens {
            return "Dim the room. The flash lights up every camera lens as a sharp, steady glint. Sweep slowly across the room, mirrors, vents and furniture."
        }
        return "Uses the front camera, which can see infrared. Turn off the lights and look for bright white or purple points. Night-vision cameras glow even in darkness."
    }

    private var tooBrightLimit: Double {
        mode == .lens ? 150 : 90
    }

    private var lightText: String {
        if camera.ambient < 40 { return "Dark" }
        if camera.ambient < 90 { return "Dim" }
        return "Bright"
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    InfoCard(symbol: tool.symbol, title: tool.title, text: introText)
                    if camera.denied {
                        deniedCard
                    } else {
                        viewfinder
                        statusRow
                    }
                    controls
                }
                .padding(16)
            }
        }
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            finish()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sensoryFeedback(trigger: camera.hotspots.count) { (old: Int, new: Int) -> SensoryFeedback? in
            if new > old {
                return .warning
            }
            return nil
        }
    }

    private var viewfinder: some View {
        ZStack {
            Color.black
            if running {
                CameraPreview(session: camera.session)
                GeometryReader { geo in
                    ForEach(camera.hotspots) { (spot: Hotspot) in
                        HotspotMarker(strength: spot.strength)
                            .position(x: spot.x * geo.size.width, y: spot.y * geo.size.height)
                    }
                }
                .animation(.spring(duration: 0.3), value: camera.hotspots.count)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    Text("Tap Start to open the camera")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .frame(maxHeight: 460)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1.5)
        )
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            if running {
                if camera.ambient > tooBrightLimit {
                    StatusChip(risk: .caution, text: "Too bright. Dim the lights")
                } else {
                    StatusChip(risk: camera.hotspots.isEmpty ? .clear : .danger,
                               text: camera.hotspots.isEmpty ? "Nothing detected" : "\(camera.hotspots.count) suspicious point(s)")
                }
                Spacer()
                Text("Light: \(lightText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Spacer()
            }
        }
        .animation(.spring(duration: 0.3), value: camera.hotspots.count)
    }

    private var deniedCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.warn)
            Text("Camera access is off")
                .font(.system(.headline, design: .rounded))
            Text("Allow camera access in Settings to use this scan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private var controls: some View {
        Button {
            if running {
                finish()
            } else {
                camera.start(mode: mode)
                withAnimation(.spring(duration: 0.3)) {
                    running = true
                }
            }
        } label: {
            Label(running ? "Stop scan" : "Start scan", systemImage: running ? "stop.fill" : "play.fill")
        }
        .buttonStyle(PrimaryButtonStyle(colors: running ? [Theme.danger, Color(red: 0.75, green: 0.18, blue: 0.3)] : [Theme.accent, Theme.accentDeep]))
    }

    private func finish() {
        guard running else { return }
        camera.stop()
        withAnimation(.spring(duration: 0.3)) {
            running = false
        }
        guard camera.frames > 150 else { return }
        let n: Int = camera.peakHotspots
        if mode == .lens {
            if n == 0 {
                store.report(.lens, .clear, "No lens reflections detected")
            } else if n >= 4 {
                store.report(.lens, .danger, "\(n) lens-like glints found")
            } else {
                store.report(.lens, .caution, "\(n) lens-like glint(s). Check them by eye.")
            }
        } else {
            if n == 0 {
                store.report(.infrared, .clear, "No infrared light sources seen")
            } else if n >= 3 {
                store.report(.infrared, .danger, "\(n) infrared light sources found")
            } else {
                store.report(.infrared, .caution, "\(n) infrared source(s). Check them by eye.")
            }
        }
    }
}
