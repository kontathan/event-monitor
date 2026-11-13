import Foundation

/// Ein vom Nutzer hinzugefügter Kalender im offenen iCalendar-Format (.ics).
public struct ICalFeed: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var url: URL
    public var city: City
    public var isEnabled: Bool
    /// Ort für Termine, deren Feed keinen eigenen Ort nennt (z. B. „Haus Mainusch“).
    public var defaultVenue: String?

    public init(id: UUID = UUID(), name: String, url: URL, city: City, defaultVenue: String? = nil,
                isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.url = url
        self.city = city
        self.defaultVenue = defaultVenue
        self.isEnabled = isEnabled
    }

    /// Wandelt `webcal://` in `https://` um; akzeptiert nur http(s).
    public static func normalizedURL(from string: String) -> URL? {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("webcal://") {
            text = "https://" + text.dropFirst("webcal://".count)
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host() != nil else { return nil }
        return url
    }
}

/// Alle Einstellungen der App. Wird als lesbares JSON gespeichert.
public struct AppSettings: Codable, Equatable, Sendable {
    public var exclusionRules: [ExclusionRule] = []
    public var customFeeds: [ICalFeed] = []
    public var disabledSourceIDs: Set<String> = []
    /// Wie viele Tage im Voraus gescannt wird.
    public var scanDays: Int = 60
    public var autoScanOnLaunch: Bool = true
    /// Kategorien, die unter „Meine Interessen“ zusammengefasst werden.
    public var interests: Set<EventCategory> = []

    public init() {}

    // Eigene Dekodierung, damit ältere Einstellungsdateien mit fehlenden Feldern weiter funktionieren.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exclusionRules = try c.decodeIfPresent([ExclusionRule].self, forKey: .exclusionRules) ?? []
        customFeeds = try c.decodeIfPresent([ICalFeed].self, forKey: .customFeeds) ?? []
        disabledSourceIDs = try c.decodeIfPresent(Set<String>.self, forKey: .disabledSourceIDs) ?? []
        scanDays = try c.decodeIfPresent(Int.self, forKey: .scanDays) ?? 60
        autoScanOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .autoScanOnLaunch) ?? true
        interests = try c.decodeIfPresent(Set<EventCategory>.self, forKey: .interests) ?? []
    }
}

/// Ergebnis des letzten Scans – wird gespeichert, damit die App sofort etwas anzeigt.
public struct EventCache: Codable, Sendable {
    public var events: [Event]
    public var scannedAt: Date?

    public init(events: [Event], scannedAt: Date?) {
        self.events = events
        self.scannedAt = scannedAt
    }
}
