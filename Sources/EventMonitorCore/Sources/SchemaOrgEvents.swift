import Foundation

/// Liest Veranstaltungen aus Webseiten, die sie im offenen schema.org-Format (JSON-LD) einbetten.
/// Viele Clubs und Kulturorte tun das, damit Suchmaschinen ihre Termine verstehen.
public enum SchemaOrgEvents {
    public static func parse(html: String, baseURL: URL, city: City, sourceID: String) -> [Event] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script[^>]*application/ld\+json[^>]*>([\s\S]*?)</script>"#,
            options: [.caseInsensitive]
        ) else { return [] }

        var events: [Event] = []
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let r = Range(match.range(at: 1), in: html),
                  let json = try? JSONSerialization.jsonObject(with: Data(html[r].utf8)) else { continue }
            collect(json, into: &events, baseURL: baseURL, city: city, sourceID: sourceID)
        }
        var seen = Set<String>()
        return events.filter { seen.insert($0.id).inserted }
    }

    static func collect(_ node: Any, into events: inout [Event], baseURL: URL, city: City, sourceID: String) {
        if let array = node as? [Any] {
            for item in array { collect(item, into: &events, baseURL: baseURL, city: city, sourceID: sourceID) }
            return
        }
        guard let dict = node as? [String: Any] else { return }
        let types = (dict["@type"] as? [String]) ?? [(dict["@type"] as? String) ?? ""]
        if types.contains(where: { $0.hasSuffix("Event") }), let event = makeEvent(dict, baseURL: baseURL, city: city, sourceID: sourceID) {
            events.append(event)
        }
        for value in dict.values where value is [Any] || value is [String: Any] {
            collect(value, into: &events, baseURL: baseURL, city: city, sourceID: sourceID)
        }
    }

    static func makeEvent(_ dict: [String: Any], baseURL: URL, city: City, sourceID: String) -> Event? {
        guard let rawName = dict["name"] as? String,
              case let name = HTMLText.decodeEntities(rawName).trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let startText = dict["startDate"] as? String,
              let (start, isAllDay) = parseDate(startText)
        else { return nil }

        var end = (dict["endDate"] as? String).flatMap { parseDate($0)?.date }
        if let e = end, e <= start { end = nil }

        let url = (dict["url"] as? String).flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        let description = (dict["description"] as? String).map { HTMLText.plain($0) }

        return Event(
            id: "\(sourceID):\(url?.absoluteString ?? name):\(Int(start.timeIntervalSince1970))",
            seriesID: "\(sourceID):\(name.searchFolded)",
            title: name,
            summary: description?.nilIfEmpty,
            venue: venue(from: dict["location"]),
            city: city,
            start: start,
            end: end,
            isAllDay: isAllDay,
            url: url ?? baseURL,
            price: price(from: dict) ?? PriceParser.parse(description),
            sourceID: sourceID
        )
    }

    static func venue(from location: Any?) -> String? {
        if let text = location as? String { return text.nilIfEmpty }
        if let list = location as? [Any] { return venue(from: list.first) }
        guard let dict = location as? [String: Any] else { return nil }
        if let name = dict["name"] as? String, !name.isEmpty { return HTMLText.decodeEntities(name) }
        if let address = dict["address"] as? String { return address.nilIfEmpty }
        if let address = dict["address"] as? [String: Any] {
            return [address["streetAddress"] as? String, address["addressLocality"] as? String]
                .compactMap { $0 }.joined(separator: ", ").nilIfEmpty
        }
        return nil
    }

    static func price(from dict: [String: Any]) -> PriceInfo? {
        if dict["isAccessibleForFree"] as? Bool == true { return .free }
        let offers: [[String: Any]]
        if let list = dict["offers"] as? [[String: Any]] { offers = list }
        else if let single = dict["offers"] as? [String: Any] { offers = [single] }
        else { return nil }

        let amounts: [Double] = offers.flatMap { offer -> [Double] in
            [offer["price"], offer["lowPrice"], offer["highPrice"]].compactMap { value in
                if let number = value as? Double { return number }
                if let number = value as? Int { return Double(number) }
                if let text = value as? String { return Double(text.replacingOccurrences(of: ",", with: ".")) }
                return nil
            }
        }
        guard !amounts.isEmpty else { return nil }
        let positive = amounts.filter { $0 > 0 }
        return positive.isEmpty ? .free : .paid(positive)
    }

    /// ISO-8601 mit oder ohne Zeitzone; ohne Zeitzone gilt Europe/Berlin. Reines Datum = ganztägig.
    static func parseDate(_ text: String) -> (date: Date, isAllDay: Bool)? {
        let value = text.trimmingCharacters(in: .whitespaces)
        if let date = try? Date(value, strategy: .iso8601) { return (date, false) }
        if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return (date, false) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = ICalendar.defaultTimeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return (date, false) }
        }
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: String(value.prefix(10))), value.count <= 10 { return (date, true) }
        return nil
    }
}
