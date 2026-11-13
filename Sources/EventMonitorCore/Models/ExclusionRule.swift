import Foundation

/// Eine Regel, die Veranstaltungen aus zukünftigen Scans ausschließt.
public struct ExclusionRule: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// Alle Termine genau dieser Veranstaltung (über `Event.seriesID`).
        case series
        /// Titel enthält ein Stichwort.
        case titleContains
        /// Veranstaltungsort enthält ein Stichwort.
        case venueContains
        /// Eine ganze Kategorie.
        case category

        public var title: String {
            switch self {
            case .series: "Veranstaltung"
            case .titleContains: "Titel enthält"
            case .venueContains: "Ort enthält"
            case .category: "Kategorie"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var value: String
    /// Lesbare Beschreibung, z. B. der Titel bei `.series`.
    public var label: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), kind: Kind, value: String, label: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.value = value
        self.label = label
        self.createdAt = createdAt
    }

    public static func series(of event: Event) -> ExclusionRule {
        ExclusionRule(kind: .series, value: event.seriesID, label: "\(event.title) (\(event.city.displayName))")
    }

    public static func venue(_ venue: String) -> ExclusionRule {
        ExclusionRule(kind: .venueContains, value: venue)
    }

    public static func keyword(_ keyword: String) -> ExclusionRule {
        ExclusionRule(kind: .titleContains, value: keyword.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func category(_ category: EventCategory) -> ExclusionRule {
        ExclusionRule(kind: .category, value: category.rawValue, label: category.title)
    }

    public var displayValue: String {
        if let label, !label.isEmpty { return label }
        return value
    }

    public func matches(_ event: Event) -> Bool {
        let needle = value.searchFolded
        guard !needle.isEmpty else { return false }
        switch kind {
        case .series:
            return event.seriesID == value
        case .titleContains:
            return event.title.searchFolded.contains(needle)
        case .venueContains:
            return (event.venue ?? "").searchFolded.contains(needle)
        case .category:
            return event.category.rawValue == value
        }
    }
}

extension Array where Element == ExclusionRule {
    public func excludes(_ event: Event) -> Bool {
        contains { $0.matches(event) }
    }
}
