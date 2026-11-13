import Foundation
import Testing
@testable import EventMonitorCore

@Suite struct PriceTests {
    @Test(arguments: [
        ("Eintritt frei!", "Kostenlos"),
        ("Der Eintritt ist frei, Spenden erwünscht.", "Kostenlos"),
        ("Kosten 62 € bei 12 Terminen", "62 €"),
        ("VVK 12 €, AK 15 Euro", "12–15 €"),
        ("Tickets: 3,99 €", "3,99 €"),
        ("Eintritt: € 8", "8 €"),
        ("Hutsammlung am Ende", "Spende"),
    ])
    func parsesLabels(text: String, expected: String) {
        #expect(PriceParser.parse(text)?.label == expected)
    }

    @Test func noPriceMeansNil() {
        #expect(PriceParser.parse("Ein schöner Abend mit Musik im Jahr 2026") == nil)
        #expect(PriceParser.parse(nil) == nil)
    }

    @Test func detailPageMainz() {
        let html = """
        <nav>Startseite</nav><h3>Eintritt und Preise</h3><dl><dt>Regulär</dt><dd>28 €</dd>
        <dt>Ermäßigt</dt><dd>18 €</dd></dl><h3>Veranstaltungsort</h3><p>Ticket-Hotline 0800 123 €uro</p>
        """
        #expect(PriceParser.fromDetailPage(html).label == "18–28 €")
    }

    @Test func detailPageFreeAndUnknown() {
        #expect(PriceParser.fromDetailPage("<h3>Eintritt und Preise</h3><p>Freier Eintritt</p>").kind == .free)
        #expect(PriceParser.fromDetailPage("<p>Nichts zum Preis</p>").kind == .unknown)
    }

    @Test func eventComputesPriceFromText() {
        let event = Event(id: "1", seriesID: "s", title: "Konzert", summary: "Eintritt frei", city: .mainz,
                          start: .now, sourceID: "t")
        #expect(event.price == .free)
    }
}

@Suite struct SchemaOrgTests {
    let html = """
    <html><head><script type="application/ld+json">
    {"@context":"https://schema.org","@graph":[
      {"@type":"MusicEvent","name":"BOY HARSHER","startDate":"2026-11-17T20:00:00+01:00",
       "location":{"@type":"Place","name":"ZOOM Frankfurt"},"url":"/events/boy-harsher",
       "offers":{"@type":"Offer","price":"29.50","priceCurrency":"EUR"}},
      {"@type":"Event","name":"Open Air &amp; Friends","startDate":"2026-11-20","isAccessibleForFree":true,
       "location":"Hafen"},
      {"@type":"WebPage","name":"Kein Event"}
    ]}
    </script></head></html>
    """

    @Test func parsesEventsWithPrices() {
        let events = SchemaOrgEvents.parse(html: html, baseURL: URL(string: "https://zoomfrankfurt.com/")!,
                                           city: .frankfurt, sourceID: "zoom")
        #expect(events.count == 2)
        #expect(events[0].title == "BOY HARSHER")
        #expect(events[0].venue == "ZOOM Frankfurt")
        #expect(events[0].url?.absoluteString == "https://zoomfrankfurt.com/events/boy-harsher")
        #expect(events[0].price?.label == "29,50 €")
        #expect(events[0].city == .frankfurt)
        #expect(events[1].title == "Open Air & Friends")
        #expect(events[1].isAllDay)
        #expect(events[1].price == .free)
    }
}

@Suite struct DemoCategoryTests {
    @Test(arguments: [
        ("Demo gegen Rechts", EventCategory.demo),
        ("Kundgebung am Hauptbahnhof", .demo),
        ("Mahnwache für den Frieden", .demo),
        ("Demokratie braucht Bildung – Vortrag", .politik),
        ("Krempelmarkt am Rheinufer", .markt),
    ])
    func categorizes(title: String, expected: EventCategory) {
        #expect(Categorizer.category(kicker: nil, title: title, text: nil) == expected)
    }
}
