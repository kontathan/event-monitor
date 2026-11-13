import Foundation

/// Eine Stadt, für die Veranstaltungen gesammelt werden.
public enum City: String, Codable, CaseIterable, Identifiable, Sendable {
    case mainz
    case wiesbaden
    case frankfurt

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mainz: "Mainz"
        case .wiesbaden: "Wiesbaden"
        case .frankfurt: "Frankfurt"
        }
    }

    /// Erkennt die Stadt in einer Adresse – über das Wort selbst oder die Postleitzahl.
    /// „Mainzer Landstraße“ (Frankfurt) zählt bewusst nicht als Mainz.
    public static func detect(in address: String?) -> City? {
        guard let address else { return nil }
        let words = address.searchFolded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for word in words {
            switch word {
            case "mainz": return .mainz
            case "wiesbaden": return .wiesbaden
            case "frankfurt": return .frankfurt
            default:
                guard word.count == 5, let plz = Int(word) else { continue }
                if (55116...55131).contains(plz) { return .mainz }
                if (65183...65207).contains(plz) { return .wiesbaden }
                if (60306...60599).contains(plz) || (65929...65936).contains(plz) { return .frankfurt }
            }
        }
        return nil
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
    /// Eintritt, falls die Quelle ihn nennt (sonst evtl. später von der Detailseite nachgeladen).
    public var price: PriceInfo?
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
        price: PriceInfo? = nil,
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
        self.category = category ?? Categorizer.category(kicker: sourceCategory, title: title, venue: venue, text: summary)
        self.price = price ?? PriceParser.parse([title, summary ?? ""].joined(separator: "\n"))
        self.sourceID = sourceID
    }

    /// Kategorie neu bestimmen – z. B. nach Änderungen an den Stichwörtern für zwischengespeicherte Termine.
    public func recategorized() -> Event {
        var copy = self
        copy.category = Categorizer.category(kicker: sourceCategory, title: title, venue: venue, text: summary)
        if copy.price == nil { copy.price = PriceParser.parse([title, summary ?? ""].joined(separator: "\n")) }
        return copy
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
