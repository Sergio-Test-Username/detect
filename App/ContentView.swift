import SwiftUI

struct ContentView: View {
    @StateObject private var store = ScanStore()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        StatusHero()
                        ToolGrid()
                        TipsCard()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("LensGuard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(duration: 0.4)) {
                            store.reset()
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("Reset results")
                }
            }
            .navigationDestination(for: Tool.self) { (tool: Tool) in
                ToolDestination(tool: tool)
            }
        }
        .environmentObject(store)
        .tint(Theme.accent)
    }
}

struct ToolDestination: View {
    let tool: Tool

    var body: some View {
        switch tool {
        case .network: NetworkView()
        case .bluetooth: BluetoothView()
        case .lens: CameraScanView(mode: .lens)
        case .infrared: CameraScanView(mode: .infrared)
        case .magnetic: MagnetView()
        case .checklist: ChecklistView()
        }
    }
}

struct StatusHero: View {
    @EnvironmentObject var store: ScanStore

    private var headline: String {
        switch store.overall {
        case .unknown: return "Ready to sweep"
        case .clear: return "Looks clear so far"
        case .caution: return "Something looks off"
        case .danger: return "Possible camera found"
        }
    }

    private var subline: String {
        let total = Tool.allCases.count
        switch store.overall {
        case .unknown: return "Run each check below for the most reliable result."
        case .danger: return "\(store.completed) of \(total) checks done. Inspect flagged items in person."
        default: return "\(store.completed) of \(total) checks done. More checks mean more confidence."
        }
    }

    var body: some View {
        let risk: Risk = store.overall
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(store.progress, 0.02))
                    .stroke(risk.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: risk.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(risk.color)
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(subline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
        .animation(.spring(duration: 0.5), value: store.overall)
        .animation(.spring(duration: 0.5), value: store.progress)
        .sensoryFeedback(.selection, trigger: store.overall)
    }
}

struct ToolGrid: View {
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Tool.allCases) { (tool: Tool) in
                NavigationLink(value: tool) {
                    ToolCard(tool: tool)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ToolCard: View {
    let tool: Tool
    @EnvironmentObject var store: ScanStore

    var body: some View {
        let result: ToolResult? = store.results[tool]
        let risk: Risk = result?.risk ?? .unknown
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: tool.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Theme.primaryGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            Text(tool.title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
            Text(result?.summary ?? tool.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            StatusChip(risk: risk)
        }
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .cardStyle()
    }
}

struct TipsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("For best results", systemImage: "lightbulb.fill")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.warn)
            Text("Turn off the room lights for the lens and IR scans, move slowly, and sweep every angle of the bed, bathroom and seating area. Connect to the room's Wi-Fi for the network scan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("No app can guarantee that a room is free of cameras. Treat results as clues and follow up with a physical inspection.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
