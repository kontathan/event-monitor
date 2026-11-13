import Foundation
import Testing
@testable import EventMonitorCore

// MARK: - Hilfen

private func date(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

private func event(_ title: String, venue: String? = nil, series: String = "s", start: String = "2026-11-20T20:00:00+01:00",
                   kicker: String? = nil) -> Event {
    Event(id: UUID().uuidString, seriesID: series, title: title, venue: venue, city: .mainz,
          start: date(start), sourceCategory: kicker, sourceID: "test")
}

// MARK: - Sitepark (mainz.de / wiesbaden.de)

@Suite struct SiteparkParsingTests {
    let fixture = """
    {"data":{"searchEvents":{"total":2,"results":[
      {"id":"info-networking-event-165076-267748","teaser":{"__typename":"EventTeaser","headline":"Wochenmarkt in Bretzenheim",
       "text":"Erste Zeile | Zweite Zeile","kicker":"Veranstaltungskalender",
       "link":{"url":"/info-networking-event?id=165076&eventId=267748&spfix%3AscheduleId=0"},"venue":"Bahnstraße",
       "schedulings":[{"start":"2026-11-13T07:00:00+01:00","end":"2026-11-13T13:00:00+01:00","isFullDay":false,"hasStartTime":true,"hasEndTime":true}]}},
      {"id":"info-networking-event-169344-1","teaser":{"__typename":"EventTeaser","headline":"FILMZ – Symposium",
       "text":null,"kicker":"Kino | Online-Buchung","link":{"url":"/info-networking-event?id=169344"},"venue":null,
       "schedulings":[{"start":"2026-11-13T20:00:00+01:00","end":"2026-11-13T19:30:00+01:00","isFullDay":false,"hasStartTime":true,"hasEndTime":true}]}}
    ]}}}
    """

    @Test func parsesEvents() throws {
        let page = try SiteparkEventSource.parse(Data(fixture.utf8), baseURL: URL(string: "https://www.mainz.de")!,
                                                 city: .mainz, sourceID: "mainz.de")
        #expect(page.total == 2)
        #expect(page.events.count == 2)

        let market = page.events[0]
        #expect(market.title == "Wochenmarkt in Bretzenheim")
        #expect(market.seriesID == "mainz.de:165076")
        #expect(market.summary == "Erste Zeile\nZweite Zeile")
        #expect(market.url?.absoluteString.hasPrefix("https://www.mainz.de/info-networking-event?id=165076") == true)
        #expect(market.end == date("2026-11-13T13:00:00+01:00"))
        #expect(market.category == .markt)

        let film = page.events[1]
        #expect(film.end == nil, "Ende vor Start wird verworfen")
        #expect(film.venue == nil)
        #expect(film.category == .kino)
    }

    @Test func graphQLErrorIsThrown() {
        let data = Data(#"{"errors":[{"message":"kaputt"}]}"#.utf8)
        #expect(throws: SourceError.self) {
            try SiteparkEventSource.parse(data, baseURL: URL(string: "https://x.de")!, city: .mainz, sourceID: "x")
        }
    }

    @Test func requestContainsDateRange() throws {
        let request = try BuiltInSources.wiesbaden.makeRequest(offset: 500, days: 30)
        #expect(request.url?.absoluteString == "https://www.wiesbaden.de/api/graphql/")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("P30D"))
        #expect(body.contains("\"offset\":500"))
    }
}

// MARK: - iCalendar

@Suite struct ICalendarTests {
    let sample = """
    BEGIN:VCALENDAR\r
    VERSION:2.0\r
    BEGIN:VEVENT\r
    UID:abc-1\r
    SUMMARY:Jazz im Hof\\, mit Gästen\r
    DESCRIPTION:Zeile eins\\nZeile zwei mit einem sehr langen Text der umgebrochen \r
     wurde\r
    DTSTART;TZID=Europe/Berlin:20261120T200000\r
    DTEND;TZID=Europe/Berlin:20261120T223000\r
    LOCATION:Hof\\; Altstadt\r
    CATEGORIES:Musik,Jazz\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:abc-2\r
    SUMMARY:Flohmarkt\r
    DTSTART;VALUE=DATE:20261121\r
    DTEND;VALUE=DATE:20261122\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:abc-3\r
    SUMMARY:UTC-Termin\r
    DTSTART:20261121T090000Z\r
    END:VEVENT\r
    END:VCALENDAR\r
    """

    @Test func parsesFoldedEscapedAndDates() {
        let events = ICalendar.parse(sample, city: .wiesbaden, sourceID: "feed")
        #expect(events.count == 3)

        let jazz = events[0]
        #expect(jazz.title == "Jazz im Hof, mit Gästen")
        #expect(jazz.summary == "Zeile eins\nZeile zwei mit einem sehr langen Text der umgebrochen wurde")
        #expect(jazz.venue == "Hof; Altstadt")
        #expect(jazz.start == date("2026-11-20T20:00:00+01:00"))
        #expect(jazz.end == date("2026-11-20T22:30:00+01:00"))
        #expect(jazz.sourceCategory == "Musik")
        #expect(jazz.category == .konzert)
        #expect(jazz.city == .wiesbaden)

        let flea = events[1]
        #expect(flea.isAllDay)
        #expect(flea.start == date("2026-11-21T00:00:00+01:00"))
        #expect(flea.category == .markt)

        #expect(events[2].start == date("2026-11-21T09:00:00Z"))
    }

    @Test func exportRoundTrip() {
        let original = Event(id: "x1", seriesID: "x", title: "Lesung; mit, Sonderzeichen", summary: "Text\nZweite Zeile",
                             venue: "Stadtbibliothek", city: .mainz, start: date("2026-12-01T19:00:00+01:00"),
                             end: date("2026-12-01T21:00:00+01:00"), url: URL(string: "https://example.org/e"),
                             sourceID: "t")
        let text = ICalendar.export([original])
        #expect(text.split(separator: "\r\n").allSatisfy { $0.utf8.count <= 75 })

        let parsed = ICalendar.parse(text, city: .mainz, sourceID: "t")
        #expect(parsed.count == 1)
        #expect(parsed[0].title == original.title)
        #expect(parsed[0].start == original.start)
        #expect(parsed[0].end == original.end)
        #expect(parsed[0].venue == "Stadtbibliothek, Mainz")
    }

    @Test func webcalIsNormalized() {
        #expect(ICalFeed.normalizedURL(from: "webcal://example.org/cal.ics")?.absoluteString == "https://example.org/cal.ics")
        #expect(ICalFeed.normalizedURL(from: "ftp://example.org/cal.ics") == nil)
        #expect(ICalFeed.normalizedURL(from: "kein link") == nil)
    }
}

// MARK: - Kategorien

@Suite struct CategorizerTests {
    @Test(arguments: [
        ("Flohmarkt an der Uni Mainz", nil, EventCategory.markt),
        ("Stadtführung - Altstadt und St. Stephan", nil, .fuehrung),
        ("Aufführung: Der Sturm", nil, .buehne),
        ("Liedfett – Club Tour", "Konzerte / Musik | Gläubige", .konzert),
        ("Blind Date mit Wiesbaden", "Führungen | Wein", .fuehrung),
        ("QiGong - jeden Freitag", nil, .sport),
        ("Podiumsdiskussion zur Kommunalwahl", nil, .politik),
        ("Nicht nur zur Weihnachtszeit | Lesung und Diskussion", nil, .politik),
        ("Gedenken an die Opfer des Nationalsozialismus", nil, .geschichte),
        ("Die Römer in Mainz", nil, .geschichte),
        ("Vernissage: Zwischen Haut und Horizont", nil, .ausstellung),
        ("Weihnachtsgeschichten für Kinder", nil, .kinder),
        ("Infoabend Studium", nil, .bildung),
        ("Irgendwas Neues", nil, .sonstiges)
    ] as [(String, String?, EventCategory)])
    func categorizes(title: String, kicker: String?, expected: EventCategory) {
        #expect(Categorizer.category(kicker: kicker, title: title, text: nil) == expected)
    }

    @Test func venueHelpsWhenTitleIsVague() {
        #expect(Categorizer.category(kicker: nil, title: "Open Sunday", venue: "Kunsthalle Mainz", text: nil) == .ausstellung)
        #expect(Categorizer.category(kicker: nil, title: "Abendprogramm", venue: "Landesmuseum Mainz", text: nil) == .geschichte)
        #expect(Categorizer.category(kicker: nil, title: "Treffen", venue: "Haus des Erinnerns", text: nil) == .politik)
        // Der Titel hat Vorrang vor dem Ort.
        #expect(Categorizer.category(kicker: nil, title: "Orgelkonzert", venue: "Landesmuseum Mainz", text: nil) == .konzert)
    }

    @Test func universityNameIsNotHistory() {
        #expect(Categorizer.category(kicker: nil, title: "Infoabend", venue: "Johannes Gutenberg-Universität", text: nil) != .geschichte)
    }

    @Test func textOnlyMatchesSpecificWords() {
        // „Sie haben die Wahl“ ist keine Politik, „Geschichten“ keine Geschichte.
        #expect(Categorizer.category(kicker: nil, title: "Live Video-Chat", text: "Sie haben die Wahl: zuhören oder fragen.") == .sonstiges)
        #expect(Categorizer.category(kicker: nil, title: "Quizabend", text: "Lustige Geschichten und Fragen") == .sonstiges)
        #expect(Categorizer.category(kicker: nil, title: "Abend im Hof", text: "Ein Blick in die Geschichte des Hauses") == .geschichte)
    }

    @Test func meaninglessKickerIsIgnored() {
        #expect(Categorizer.category(kicker: "Veranstaltungskalender", title: "Jazzabend", text: nil) == .konzert)
    }
}

// MARK: - Ausschlüsse & Scanner

@Suite struct ExclusionTests {
    @Test func ruleKinds() {
        let market = event("Wochenmarkt Bretzenheim", venue: "Bahnstraße", series: "mainz.de:1")
        #expect(ExclusionRule.series(of: market).matches(market))
        #expect(!ExclusionRule.series(of: market).matches(event("Wochenmarkt Bretzenheim", series: "mainz.de:2")))
        #expect(ExclusionRule.keyword("wochenmarkt").matches(market))
        #expect(ExclusionRule.venue("bahnstrasse").matches(market)) // „ß“ und „ss“ gelten als gleich
        #expect(ExclusionRule.venue("BAHNSTRASSE").matches(event("x", venue: "BAHNSTRASSE")))
        #expect(ExclusionRule.category(.markt).matches(market))
        #expect(!ExclusionRule.keyword("   ").matches(market))
        #expect(ExclusionRule(kind: .titleContains, value: "fuhrung").matches(event("Stadtführung")))
    }

    @Test func processFiltersDedupesAndSorts() {
        let now = date("2026-11-13T12:00:00+01:00")
        let past = event("Vorbei", start: "2026-11-12T20:00:00+01:00")
        let late = event("Später", series: "a", start: "2026-11-15T20:00:00+01:00")
        let early = event("Früher", series: "b", start: "2026-11-14T20:00:00+01:00")
        let excluded = event("Gymnastik am Morgen", series: "c", start: "2026-11-14T09:00:00+01:00")

        let result = EventScanner.process([past, late, early, early, excluded],
                                          rules: [.keyword("gymnastik")], now: now)
        #expect(result.events.map(\.title) == ["Früher", "Später"])
        #expect(result.excluded == 1)
    }

    @Test func settingsDecodeWithMissingFields() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"scanDays": 14}"#.utf8))
        #expect(settings.scanDays == 14)
        #expect(settings.exclusionRules.isEmpty)
        #expect(settings.autoScanOnLaunch)
        #expect(settings.interests.isEmpty)

        let withInterests = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"interests": ["politik", "konzert"]}"#.utf8))
        #expect(withInterests.interests == [.politik, .konzert])
    }

    @Test func scannerReportsFailuresAndAppliesRules() async {
        struct Stub: EventSource {
            var id: String; var displayName: String; var city: City = .mainz; var result: Result<[Event], SourceError>
            func fetchEvents(days: Int, client: any HTTPClient) async throws -> [Event] { try result.get() }
        }
        let future = event("Konzert", series: "k", start: "2030-01-01T20:00:00+01:00")
        let unwanted = event("Rückengymnastik", series: "g", start: "2030-01-01T10:00:00+01:00")
        let scanner = EventScanner(
            sources: [Stub(id: "a", displayName: "A", result: .success([future, unwanted])),
                      Stub(id: "b", displayName: "B", result: .failure(.http(status: 503)))],
            rules: [.series(of: unwanted)], days: 30)

        let result = await scanner.scan()
        #expect(result.events.map(\.title) == ["Konzert"])
        #expect(result.excludedCount == 1)
        #expect(result.failures.map(\.sourceName) == ["B"])
    }
}

// MARK: - Live-Test (nur mit EVENTMONITOR_LIVE=1)

@Suite(.enabled(if: ProcessInfo.processInfo.environment["EVENTMONITOR_LIVE"] == "1"))
struct LiveTests {
    @Test(arguments: BuiltInSources.all)
    func cityCalendarDeliversEvents(source: SiteparkEventSource) async throws {
        let events = try await source.fetchEvents(days: 14, client: URLSession.shared)
        print("\(source.displayName): \(events.count) Termine")
        #expect(events.count > 20)
        #expect(events.allSatisfy { $0.city == source.city })
    }
}
