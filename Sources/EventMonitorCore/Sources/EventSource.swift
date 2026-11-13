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
}
