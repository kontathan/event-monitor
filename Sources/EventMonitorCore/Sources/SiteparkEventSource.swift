import Foundation

/// Liest die Veranstaltungskalender von mainz.de und wiesbaden.de.
///
/// Beide Städte nutzen dasselbe CMS (Sitepark IES). Dessen Website lädt die
/// Veranstaltungsliste über eine öffentliche GraphQL-Schnittstelle unter
/// `/api/graphql/` – genau diese Abfrage stellen wir hier auch.
public struct SiteparkEventSource: EventSource {
    public let id: String
    public let displayName: String
    public let city: City
    public let baseURL: URL
    public var pageSize = 500
    public var maxPages = 20

    public init(id: String, displayName: String, city: City, baseURL: URL) {
        self.id = id
        self.displayName = displayName
        self.city = city
        self.baseURL = baseURL
    }

    static let query = """
    query EventMonitor($input: SearchInput!) {
      searchEvents(input: $input) {
        total
        results {
          id
          teaser {
            ... on EventTeaser {
              headline text kicker venue
              link { url }
              schedulings { start end isFullDay hasStartTime hasEndTime }
            }
          }
        }
      }
    }
    """

    public func fetchEvents(days: Int, client: any HTTPClient) async throws -> [Event] {
        var events: [Event] = []
        var offset = 0
        for _ in 0..<maxPages {
            let request = try makeRequest(offset: offset, days: days)
            let data = try HTTP.checked(try await client.fetch(request))
            let page = try Self.parse(data, baseURL: baseURL, city: city, sourceID: id)
            events += page.events
            offset += page.resultCount
            if page.resultCount == 0 || offset >= page.total { break }
        }
        return events
    }

    func makeRequest(offset: Int, days: Int) throws -> URLRequest {
        let input: [String: Any] = [
            "limit": pageSize,
            "offset": offset,
            "filter": [
                ["key": "type", "objectTypes": ["infoNetworkingEvent"]],
                ["key": "range", "relativeDateRange": ["from": "P0D", "to": "P\(max(1, days))D"]]
            ],
            "sort": [["date": "ASC"]]
        ]
        let body: [String: Any] = ["query": Self.query, "variables": ["input": input]]

        var request = HTTP.request(baseURL.appending(path: "api/graphql/"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Antwort auswerten

    public struct Page: Sendable {
        public var events: [Event]
        public var resultCount: Int
        public var total: Int
    }

    public static func parse(_ data: Data, baseURL: URL, city: City, sourceID: String) throws -> Page {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let message = response.errors?.first?.message { throw SourceError.api(message) }
        guard let search = response.data?.searchEvents else { throw SourceError.invalidResponse }

        var events: [Event] = []
        for result in search.results {
            guard let teaser = result.teaser,
                  let title = teaser.headline?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
            else { continue }

            let link = teaser.link?.url.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
            let seriesID = Self.seriesID(link: teaser.link?.url, resultID: result.id, sourceID: sourceID)
            // Wiesbaden trennt Absätze mit " | ".
            let summary = teaser.text?
                .replacingOccurrences(of: " | ", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            for (index, scheduling) in (teaser.schedulings ?? []).enumerated() {
                guard let startText = scheduling.start, let start = parseDate(startText) else { continue }
                var end = scheduling.end.flatMap(parseDate)
                // Manche Einträge haben ein Ende vor dem Start oder ein Platzhalter-Ende.
                if let e = end, e < start || scheduling.hasEndTime == false { end = nil }

                events.append(Event(
                    id: index == 0 ? result.id : "\(result.id)#\(index)",
                    seriesID: seriesID,
                    title: title,
                    summary: summary?.isEmpty == false ? summary : nil,
                    venue: teaser.venue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    city: city,
                    start: start,
                    end: end,
                    isAllDay: scheduling.isFullDay == true || scheduling.hasStartTime == false,
                    url: link,
                    sourceCategory: teaser.kicker?.nilIfEmpty,
                    sourceID: sourceID
                ))
            }
        }
        return Page(events: events, resultCount: search.results.count, total: search.total)
    }

    /// Alle Termine einer Veranstaltung teilen sich den Parameter `id` im Link.
    static func seriesID(link: String?, resultID: String, sourceID: String) -> String {
        if let link,
           let id = URLComponents(string: link)?.queryItems?.first(where: { $0.name == "id" })?.value,
           !id.isEmpty {
            return "\(sourceID):\(id)"
        }
        return "\(sourceID):\(resultID)"
    }

    static func parseDate(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    // MARK: - JSON-Struktur

    struct Response: Decodable {
        var data: DataBox?
        var errors: [GraphQLError]?
    }

    struct GraphQLError: Decodable { var message: String }
    struct DataBox: Decodable { var searchEvents: SearchEvents? }

    struct SearchEvents: Decodable {
        var total: Int
        var results: [Result]
    }

    struct Result: Decodable {
        var id: String
        var teaser: Teaser?
    }

    struct Teaser: Decodable {
        var headline: String?
        var text: String?
        var kicker: String?
        var venue: String?
        var link: Link?
        var schedulings: [Scheduling]?
    }

    struct Link: Decodable { var url: String? }

    struct Scheduling: Decodable {
        var start: String?
        var end: String?
        var isFullDay: Bool?
        var hasStartTime: Bool?
        var hasEndTime: Bool?
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
