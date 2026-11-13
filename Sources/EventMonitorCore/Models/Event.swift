import Foundation

/// Eine Stadt, für die Veranstaltungen gesammelt werden.
public enum City: String, Codable, CaseIterable, Identifiable, Sendable {
    case mainz
    case wiesbaden

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mainz: "Mainz"
        case .wiesbaden: "Wiesbaden"
        }
    }
}

/// Ein einzelner Termin einer Veranstaltung.
///
/// `id` identifiziert genau diesen Termin, `seriesID` alle Termine derselben
/// Veranstaltung (z. B. jeden Freitag „Wochenmarkt“). Ausschlüsse arbeiten mit `seriesID`.
public struct Event: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var seriesID: String
    public var title: String
    public var summary: String?
    public var venue: String?
    public var city: City
    public var start: Date
    public var end: Date?
    public var isAllDay: Bool
    public var url: URL?
    /// Kategorie-Bezeichnung, wie sie die Quelle liefert (z. B. „Konzerte / Musik“).
    public var sourceCategory: String?
    public var category: EventCategory
    public var sourceID: String

    public init(
        id: String,
        seriesID: String,
        title: String,
        summary: String? = nil,
        venue: String? = nil,
        city: City,
        start: Date,
        end: Date? = nil,
        isAllDay: Bool = false,
        url: URL? = nil,
        sourceCategory: String? = nil,
        category: EventCategory? = nil,
        sourceID: String
    ) {
        self.id = id
        self.seriesID = seriesID
        self.title = title
        self.summary = summary
        self.venue = venue
        self.city = city
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.url = url
        self.sourceCategory = sourceCategory
        self.category = category ?? Categorizer.category(kicker: sourceCategory, title: title, text: summary)
        self.sourceID = sourceID
    }

    /// Geschätztes Ende: echtes Ende, sonst Tagesende (ganztägig) bzw. Start + 2 Stunden.
    public func estimatedEnd(calendar: Calendar = .current) -> Date {
        if let end, end >= start { return end }
        if isAllDay {
            let day = calendar.startOfDay(for: start)
            return calendar.date(byAdding: .day, value: 1, to: day) ?? start
        }
        return start.addingTimeInterval(2 * 3600)
    }

    public func hasEnded(at now: Date, calendar: Calendar = .current) -> Bool {
        estimatedEnd(calendar: calendar) < now
    }

    public func overlaps(_ interval: DateInterval, calendar: Calendar = .current) -> Bool {
        start < interval.end && estimatedEnd(calendar: calendar) > interval.start
    }
}

extension String {
    /// Für Vergleiche: klein geschrieben, ohne Akzente/Umlaute („Führung“ → „fuhrung“).
    public var searchFolded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }
}
