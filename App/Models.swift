import SwiftUI

enum Risk: Int, Comparable {
    case unknown = 0
    case clear
    case caution
    case danger

    static func < (lhs: Risk, rhs: Risk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var color: Color {
        switch self {
        case .unknown: return Color.gray
        case .clear: return Theme.safe
        case .caution: return Theme.warn
        case .danger: return Theme.danger
        }
    }

    var label: String {
        switch self {
        case .unknown: return "Not scanned"
        case .clear: return "Clear"
        case .caution: return "Suspicious"
        case .danger: return "Threat found"
        }
    }

    var symbol: String {
        switch self {
        case .unknown: return "circle.dashed"
        case .clear: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .danger: return "exclamationmark.octagon.fill"
        }
    }
}

enum Tool: String, CaseIterable, Identifiable, Hashable {
    case network, bluetooth, lens, infrared, magnetic, checklist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .network: return "Wi-Fi Scan"
        case .bluetooth: return "Bluetooth"
        case .lens: return "Lens Finder"
        case .infrared: return "IR Detector"
        case .magnetic: return "Magnetic"
        case .checklist: return "Checklist"
        }
    }

    var symbol: String {
        switch self {
        case .network: return "wifi"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .lens: return "camera.viewfinder"
        case .infrared: return "eye.fill"
        case .magnetic: return "waveform.path.ecg"
        case .checklist: return "checklist"
        }
    }

    var blurb: String {
        switch self {
        case .network: return "Find IP cameras on this network"
        case .bluetooth: return "Spot nearby camera transmitters"
        case .lens: return "Flash glints reveal hidden lenses"
        case .infrared: return "See night-vision LEDs"
        case .magnetic: return "Detect hidden electronics"
        case .checklist: return "Inspect the usual hiding spots"
        }
    }
}

struct ToolResult {
    var risk: Risk
    var summary: String
}

struct ChecklistItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String

    static let all: [ChecklistItem] = [
        ChecklistItem(id: "smoke", title: "Smoke detectors", detail: "Look for tiny pinholes or lenses that aren't part of the vents.", symbol: "smoke.fill"),
        ChecklistItem(id: "clock", title: "Clocks and radios", detail: "Bedside clocks are a classic disguise. Check for holes facing the bed.", symbol: "clock.fill"),
        ChecklistItem(id: "charger", title: "Chargers and outlets", detail: "Unusual USB chargers or outlet covers that face the room.", symbol: "bolt.fill"),
        ChecklistItem(id: "tv", title: "TV and set-top boxes", detail: "Check the bezel, soundbar and any boxes with a small dark window.", symbol: "tv.fill"),
        ChecklistItem(id: "vent", title: "Vents and grilles", detail: "Shine a flashlight into slats and look for a glint.", symbol: "wind"),
        ChecklistItem(id: "lamp", title: "Lamps and bulbs", detail: "Bulbs and lamp bases can hide a lens. Look for odd screws or holes.", symbol: "lightbulb.fill"),
        ChecklistItem(id: "frames", title: "Frames, books and decor", detail: "Pinholes in frames, bookshelves, tissue boxes or plants.", symbol: "photo.fill"),
        ChecklistItem(id: "plants", title: "Plants and stuffed toys", detail: "Check anything that faces the bed or shower and could hold a lens.", symbol: "leaf.fill"),
        ChecklistItem(id: "bed", title: "Headboard and furniture", detail: "Feel for anything that doesn't belong. Check behind and under.", symbol: "bed.double.fill"),
        ChecklistItem(id: "mirror", title: "Mirror fingernail test", detail: "Touch your nail to the glass. If there is no gap between it and its reflection, it may be two-way.", symbol: "hand.point.up.left.fill")
    ]
}

final class ScanStore: ObservableObject {
    @Published private(set) var results: [Tool: ToolResult] = [:]
    @Published private(set) var checked: Set<String> = []

    var overall: Risk {
        results.values.map { $0.risk }.max() ?? .unknown
    }

    var completed: Int {
        results.values.filter { $0.risk != .unknown }.count
    }

    var progress: Double {
        Double(completed) / Double(Tool.allCases.count)
    }

    func report(_ tool: Tool, _ risk: Risk, _ summary: String) {
        withAnimation(.spring(duration: 0.4)) {
            results[tool] = ToolResult(risk: risk, summary: summary)
        }
    }

    func toggle(_ id: String) {
        if checked.contains(id) {
            checked.remove(id)
        } else {
            checked.insert(id)
        }
        let total = ChecklistItem.all.count
        if checked.count == total {
            report(.checklist, .clear, "All \(total) areas inspected")
        } else if checked.isEmpty {
            results[.checklist] = nil
        } else {
            results[.checklist] = ToolResult(risk: .unknown, summary: "\(checked.count) of \(total) areas inspected")
        }
    }

    func reset() {
        results = [:]
        checked = []
    }
}
