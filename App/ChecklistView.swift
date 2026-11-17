import SwiftUI

struct ChecklistView: View {
    @EnvironmentObject var store: ScanStore

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    InfoCard(
                        symbol: "checklist",
                        title: "Inspect by hand",
                        text: "Electronic scans can miss offline cameras. Physically check these spots, using your phone's flashlight to look for lenses."
                    )
                    progressCard
                    VStack(spacing: 10) {
                        ForEach(ChecklistItem.all) { (item: ChecklistItem) in
                            ChecklistRow(item: item, isDone: store.checked.contains(item.id)) {
                                withAnimation(.spring(duration: 0.3)) {
                                    store.toggle(item.id)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Checklist")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: store.checked.count)
    }

    private var progressCard: some View {
        let total: Int = ChecklistItem.all.count
        let done: Int = store.checked.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(done) of \(total) checked")
                    .font(.system(.headline, design: .rounded))
                    .contentTransition(.numericText())
                Spacer()
                if done == total {
                    StatusChip(risk: .clear, text: "Complete")
                }
            }
            ProgressView(value: Double(done), total: Double(total))
                .tint(done == total ? Theme.safe : Theme.accent)
        }
        .cardStyle()
        .animation(.spring(duration: 0.3), value: done)
    }
}

struct ChecklistRow: View {
    let item: ChecklistItem
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: item.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(isDone ? Theme.safe : Color.secondary.opacity(0.5))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isDone ? Theme.safe.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
