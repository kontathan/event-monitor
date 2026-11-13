import Foundation

/// Lesen und Schreiben des offenen iCalendar-Formats (RFC 5545).
///
/// Bewusst schlank: Wiederholungsregeln (RRULE) werden nicht expandiert,
/// es zählt der erste Termin eines VEVENT.
public enum ICalendar {
    static let defaultTimeZone = TimeZone(identifier: "Europe/Berlin")!

    // MARK: - Lesen

    public static func parse(_ text: String, city: City, sourceID: String) -> [Event] {
        var events: [Event] = []
        var current: [(name: String, params: [String: String], value: String)]?

        for line in unfoldedLines(text) {
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" {
                current = []
            } else if upper == "END:VEVENT" {
                if let props = current, let event = makeEvent(props, city: city, sourceID: sourceID) {
                    events.append(event)
                }
                current = nil
            } else if current != nil, let property = parseProperty(line) {
                current?.append(property)
            }
        }
        return events
    }

    /// Zeilen, die mit Leerzeichen/Tab beginnen, gehören zur vorherigen Zeile (RFC 5545, 3.1).
    static func unfoldedLines(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(String(raw))
            }
        }
        return lines
    }

    /// `NAME;PARAM=WERT:Inhalt` → (NAME, [PARAM: WERT], Inhalt)
    static func parseProperty(_ line: String) -> (name: String, params: [String: String], value: String)? {
        var inQuotes = false
        var colonIndex: String.Index?
        for index in line.indices {
            let char = line[index]
            if char == "\"" { inQuotes.toggle() }
            if char == ":" && !inQuotes { colonIndex = index; break }
        }
        guard let colonIndex else { return nil }

        let head = line[..<colonIndex]
        let value = String(line[line.index(after: colonIndex)...])
        var parts = head.split(separator: ";").map(String.init)
        guard !parts.isEmpty else { return nil }
        let name = parts.removeFirst().uppercased()

        var params: [String: String] = [:]
        for part in parts {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            params[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return (name, params, value)
    }

    static func makeEvent(_ props: [(name: String, params: [String: String], value: String)],
                          city: City, sourceID: String) -> Event? {
        func first(_ name: String) -> (params: [String: String], value: String)? {
            props.first { $0.name == name }.map { ($0.params, $0.value) }
        }

        guard let title = first("SUMMARY").map({ unescape($0.value) })?.trimmingCharacters(in: .whitespaces),
              !title.isEmpty,
              let startProp = first("DTSTART"),
              let (start, isAllDay) = parseDate(startProp.value, params: startProp.params)
        else { return nil }

        var end = first("DTEND").flatMap { parseDate($0.value, params: $0.params)?.date }
        if isAllDay, let e = end {
            // Bei ganztägigen Terminen ist DTEND exklusiv (Folgetag 0 Uhr).
            end = e.addingTimeInterval(-1)
        }
        if let e = end, e < start { end = nil }

        let uid = first("UID")?.value ?? "\(title)-\(start.timeIntervalSince1970)"
        let categories = first("CATEGORIES").map { unescape($0.value) }
        let firstCategory = categories?.split(separator: ",").first.map {
            String($0).trimmingCharacters(in: .whitespaces)
        }

        return Event(
            id: "\(sourceID):\(uid):\(Int(start.timeIntervalSince1970))",
            seriesID: "\(sourceID):\(uid)",
            title: title,
            summary: first("DESCRIPTION").map { unescape($0.value) }?.nilIfEmpty,
            venue: first("LOCATION").map { unescape($0.value) }?.nilIfEmpty,
            city: city,
            start: start,
            end: end,
            isAllDay: isAllDay,
            url: first("URL").flatMap { URL(string: $0.value.trimmingCharacters(in: .whitespaces)) },
            sourceCategory: firstCategory?.nilIfEmpty,
            sourceID: sourceID
        )
    }

    /// Unterstützt `20261113`, `20261113T200000`, `20261113T190000Z` sowie `TZID=…`.
    static func parseDate(_ rawValue: String, params: [String: String]) -> (date: Date, isAllDay: Bool)? {
        let value = rawValue.trimmingCharacters(in: .whitespaces)
        let chars = Array(value)
        func number(_ range: Range<Int>) -> Int? {
            guard range.upperBound <= chars.count else { return nil }
            return Int(String(chars[range]))
        }
        guard let year = number(0..<4), let month = number(4..<6), let day = number(6..<8) else { return nil }

        let isUTC = value.hasSuffix("Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = isUTC
            ? TimeZone(identifier: "UTC")!
            : params["TZID"].flatMap(TimeZone.init(identifier:)) ?? defaultTimeZone

        var components = DateComponents(year: year, month: month, day: day)
        let isAllDay = params["VALUE"]?.uppercased() == "DATE" || chars.count == 8
        if !isAllDay {
            guard chars.count >= 15, chars[8] == "T",
                  let hour = number(9..<11), let minute = number(11..<13), let second = number(13..<15)
            else { return nil }
            components.hour = hour
            components.minute = minute
            components.second = second
        }
        return calendar.date(from: components).map { ($0, isAllDay) }
    }

    static func unescape(_ text: String) -> String {
        var result = ""
        var iterator = text.makeIterator()
        while let char = iterator.next() {
            guard char == "\\", let next = iterator.next() else { result.append(char); continue }
            switch next {
            case "n", "N": result.append("\n")
            default: result.append(next) // \, \; \\
            }
        }
        return result
    }

    // MARK: - Schreiben

    /// Erzeugt eine .ics-Datei, die jede Kalender-App (Apple Kalender, Thunderbird, …) importieren kann.
    public static func export(_ events: [Event], now: Date = .now) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//EventMonitor//Open Source//DE",
            "CALSCALE:GREGORIAN"
        ]
        for event in events {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(escape(event.id))@event-monitor")
            lines.append("DTSTAMP:\(utcStamp(now))")
            if event.isAllDay {
                let startDay = dateStamp(event.start)
                let endDate = Calendar.berlin.date(byAdding: .day, value: 1,
                                                  to: Calendar.berlin.startOfDay(for: event.end ?? event.start))!
                lines.append("DTSTART;VALUE=DATE:\(startDay)")
                lines.append("DTEND;VALUE=DATE:\(dateStamp(endDate))")
            } else {
                lines.append("DTSTART:\(utcStamp(event.start))")
                lines.append("DTEND:\(utcStamp(event.end ?? event.start.addingTimeInterval(3600)))")
            }
            lines.append("SUMMARY:\(escape(event.title))")
            let location = [event.venue, event.city.displayName].compactMap { $0 }.joined(separator: ", ")
            lines.append("LOCATION:\(escape(location))")
            var description = event.summary ?? ""
            if let url = event.url { description += (description.isEmpty ? "" : "\n\n") + url.absoluteString }
            if !description.isEmpty { lines.append("DESCRIPTION:\(escape(description))") }
            if let url = event.url { lines.append("URL:\(url.absoluteString)") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.flatMap(fold).joined(separator: "\r\n") + "\r\n"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Zeilen dürfen höchstens 75 Bytes lang sein (RFC 5545, 3.1).
    static func fold(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var limit = 75
        for char in line {
            if current.utf8.count + String(char).utf8.count > limit {
                result.append(current)
                current = " "
                limit = 75
            }
            current.append(char)
        }
        result.append(current)
        return result
    }

    static func utcStamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    static func dateStamp(_ date: Date) -> String {
        let c = Calendar.berlin.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
    }
}

extension Calendar {
    static var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ICalendar.defaultTimeZone
        return calendar
    }
}

/// Ein vom Nutzer eingetragener iCal-Feed als Quelle.
public struct ICalEventSource: EventSource {
    public let feed: ICalFeed
    public var id: String { "ical:\(feed.id.uuidString)" }
    public var displayName: String { feed.name }
    public var city: City { feed.city }

    public init(feed: ICalFeed) { self.feed = feed }

    public func fetchEvents(days: Int, client: any HTTPClient) async throws -> [Event] {
        let data = try HTTP.checked(try await client.fetch(HTTP.request(feed.url)))
        let text = String(decoding: data, as: UTF8.self)
        let horizon = Date.now.addingTimeInterval(TimeInterval(days) * 86_400)
        return ICalendar.parse(text, city: feed.city, sourceID: id).filter { $0.start <= horizon }
    }
}
