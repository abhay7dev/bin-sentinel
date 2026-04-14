import Foundation

enum City: String, CaseIterable, Identifiable, Codable {
    case seattle
    case nyc
    case la
    case chicago

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .seattle: return "Seattle"
        case .nyc: return "NYC"
        case .la: return "Los Angeles"
        case .chicago: return "Chicago"
        }
    }
}

enum ScanAction: String, Codable {
    case recycle = "RECYCLE"
    case trash = "TRASH"
    case compost = "COMPOST"
    case special = "SPECIAL"
    case na = "N/A"

    var displayTitle: String {
        switch self {
        case .recycle: return "RECYCLE"
        case .trash: return "TRASH"
        case .compost: return "COMPOST"
        case .special: return "SPECIAL DISPOSAL"
        case .na: return "NO ITEM"
        }
    }
}

struct ScanResult: Codable, Identifiable {
    let item: String
    let action: String
    let reason: String
    let confidence: String
    let city: String

    var id: String { "\(item)-\(action)-\(city)-\(confidence)-\(reason)" }

    var actionEnum: ScanAction {
        ScanAction(rawValue: action) ?? .trash
    }

    /// Verdict sheet should not appear when the model found nothing meaningful to classify.
    var shouldShowVerdictPopup: Bool {
        if actionEnum == .na { return false }
        return !item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct HistoryResponse: Codable {
    let scans: [HistoryScan]
}

struct HistoryScan: Codable, Identifiable {
    let item: String
    let action: String
    let reason: String
    let confidence: String
    let city: String
    let timestamp: String

    var id: String { "\(item)-\(timestamp)-\(action)" }
}

struct APIErrorResponse: Codable {
    let error: String
    let detail: String?
}
