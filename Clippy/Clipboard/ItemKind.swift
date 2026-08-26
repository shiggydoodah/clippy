import Foundation

// Raw values are persisted directly as database values, so British spelling
// here is load-bearing rather than a style choice — `colour` must stay
// spelled this way or existing rows stop matching.
nonisolated enum ItemKind: String, Codable, Sendable {
    case text
    case link
    case image
    case file
    case colour
    case code
}
