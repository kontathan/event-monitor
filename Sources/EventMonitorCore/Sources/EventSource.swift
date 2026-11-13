import Foundation

/// Abstraktion über HTTP, damit Quellen in Tests ohne Netzwerk laufen können.
public protocol HTTPClient: Sendable {
    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {
    public func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// Eine Quelle, aus der Veranstaltungen geladen werden.
public protocol EventSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    var city: City { get }
    func fetchEvents(days: Int, client: any HTTPClient) async throws -> [Event]
}

public enum SourceError: LocalizedError, Sendable {
    case http(status: Int)
    case api(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .http(let status): "Server antwortet mit HTTP \(status)"
        case .api(let message): "Fehler der Schnittstelle: \(message)"
        case .invalidResponse: "Unerwartete Antwort vom Server"
        }
    }
}

enum HTTP {
    static let userAgent = "EventMonitor/0.1 (Open-Source macOS app)"

    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    static func checked(_ result: (Data, URLResponse)) throws -> Data {
        guard let http = result.1 as? HTTPURLResponse else { throw SourceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw SourceError.http(status: http.statusCode) }
        return result.0
    }
}

/// Die fest eingebauten Quellen: die offiziellen Veranstaltungskalender der beiden Städte.
public enum BuiltInSources {
    public static let mainz = SiteparkEventSource(
        id: "mainz.de",
        displayName: "Stadt Mainz – Veranstaltungskalender",
        city: .mainz,
        baseURL: URL(string: "https://www.mainz.de")!
    )

    public static let wiesbaden = SiteparkEventSource(
        id: "wiesbaden.de",
        displayName: "Stadt Wiesbaden – Veranstaltungskalender",
        city: .wiesbaden,
        baseURL: URL(string: "https://www.wiesbaden.de")!
    )

    public static let all: [SiteparkEventSource] = [mainz, wiesbaden]

    /// Ausgewählte Orte mit offenem Kalender (iCal oder schema.org). Lassen sich in den Einstellungen abschalten.
    public static let recommendedFeeds: [ICalFeed] = [
        ICalFeed(id: UUID(uuidString: "6B1D4C8E-1A10-4C2B-9E61-2F6F0A6C1001")!, name: "Haus Mainusch",
                 url: URL(string: "https://haus-mainusch.de/events.ics")!, city: .mainz,
                 defaultVenue: "Haus Mainusch"),
        ICalFeed(id: UUID(uuidString: "6B1D4C8E-1A10-4C2B-9E61-2F6F0A6C1002")!,
                 name: "Haus des Erinnerns – für Demokratie und Akzeptanz",
                 url: URL(string: "https://www.haus-des-erinnerns-mainz.de/events/?ical=1")!, city: .mainz,
                 defaultVenue: "Haus des Erinnerns"),
        ICalFeed(id: UUID(uuidString: "6B1D4C8E-1A10-4C2B-9E61-2F6F0A6C1003")!, name: "Kulturbäckerei Mainz",
                 url: URL(string: "https://kulturbaeckerei-mainz.de/veranstaltung/feed/ical/")!, city: .mainz,
                 defaultVenue: "Kulturbäckerei"),
        ICalFeed(id: UUID(uuidString: "6B1D4C8E-1A10-4C2B-9E61-2F6F0A6C1004")!, name: "Kreativfabrik Wiesbaden",
                 url: URL(string: "https://kreativfabrik-wiesbaden.de/veranstaltungen/?ical=1")!, city: .wiesbaden,
                 defaultVenue: "Kreativfabrik"),
        ICalFeed(id: UUID(uuidString: "6B1D4C8E-1A10-4C2B-9E61-2F6F0A6C1005")!, name: "ZOOM Frankfurt",
                 url: URL(string: "https://zoomfrankfurt.com/")!, city: .frankfurt, defaultVenue: "ZOOM"),
        // Linkes Terminportal für Frankfurt und Umgebung: Vorträge, Filme, Gedenken, Demos.
        ICalFeed(id: UUID(uuidString: "6B1D4C8E-1A10-4C2B-9E61-2F6F0A6C1006")!, name: "Frankfurter Info",
                 url: URL(string: "https://www.frankfurter-info.org/termine/@@event_listing_ical?mode=future")!,
                 city: .frankfurt)
    ]
}
