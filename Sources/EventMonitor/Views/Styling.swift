import EventMonitorCore
import SwiftUI

/// Formatierung ohne gespeicherte Formatter (die nicht thread-sicher sind).
enum Fmt {
    static let locale = Locale(identifier: "de_DE")

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale).weekday(.wide).day().month(.wide).year())
    }

    static func dayHeader(_ day: Date, calendar: Calendar = .current) -> String {
        let text = day.formatted(Date.FormatStyle(locale: locale).weekday(.wide).day().month(.wide))
        if calendar.isDateInToday(day) { return "Heute – \(text)" }
        if calendar.isDateInTomorrow(day) { return "Morgen – \(text)" }
        return text
    }

    static func timeRange(_ event: Event) -> String {
        if event.isAllDay { return "Ganztägig" }
        if let end = event.end, end > event.start, Calendar.current.isDate(end, inSameDayAs: event.start) {
            return "\(time(event.start)) – \(time(end)) Uhr"
        }
        return "ab \(time(event.start)) Uhr"
    }

    static func relative(_ date: Date) -> String {
        date.formatted(Date.RelativeFormatStyle(presentation: .named, locale: locale))
    }

    static func place(_ event: Event) -> String {
        [event.venue, event.city.displayName].compactMap { $0 }.joined(separator: " · ")
    }
}

extension EventCategory {
    var color: Color {
        switch self {
        case .markt: .orange
        case .konzert: .purple
        case .party: .pink
        case .buehne: .red
        case .demo: Color(red: 0.85, green: 0.25, blue: 0.20)
        case .politik: .cyan
        case .geschichte: .brown
        case .kino: .indigo
        case .ausstellung: .teal
        case .fuehrung: Color(red: 0.45, green: 0.55, blue: 0.30)
        case .kinder: .yellow
        case .sport: .green
        case .bildung: .blue
        case .fest: .mint
        case .sonstiges: .gray
        }
    }
}

/// Preis als dezentes Etikett; „Kostenlos“ grün hervorgehoben.
struct PriceText: View {
    let price: PriceInfo?

    var body: some View {
        if let price, let label = price.label {
            Text(label)
                .font(.callout.monospacedDigit())
                .foregroundStyle(price.kind == .free ? Color.green : Color.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
