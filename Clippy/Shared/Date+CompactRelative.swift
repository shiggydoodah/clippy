import Foundation

nonisolated extension Date {
    /// Compact age for list rows: "now", "45s", "2m", "3h", "5d".
    /// Hand-rolled because RelativeDateTimeFormatter's shortest output
    /// ("2 min. ago") is still too wide for the row layout.
    var compactRelativeDisplay: String {
        let seconds = max(0, -timeIntervalSinceNow)
        switch seconds {
        case ..<10: return "now"
        case ..<60: return "\(Int(seconds))s"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }
}
