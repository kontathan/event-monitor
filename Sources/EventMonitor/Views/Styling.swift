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
        if calendar.isDateInToday(day) { return "Heute · \(text)" }
        if calendar.isDateInTomorrow(day) { return "Morgen · \(text)" }
        return text
    }

    static func timeRange(_ event: Event) -> String {
        if event.isAllDay { return "ganztägig" }
        if let end = event.end, end > event.start, Calendar.current.isDate(end, inSameDayAs: event.start) {
            return "\(time(event.start)) – \(time(end)) Uhr"
        }
        return "ab \(time(event.start)) Uhr"
    }

    static func relative(_ date: Date) -> String {
        date.formatted(Date.RelativeFormatStyle(presentation: .named, locale: locale))
    }
}

extension EventCategory {
    var color: Color {
        switch self {
        case .markt: .orange
        case .konzert: .purple
        case .party: .pink
        case .buehne: .red
        case .kino: .indigo
        case .ausstellung: .teal
        case .fuehrung: .brown
        case .kinder: .yellow
        case .sport: .green
        case .bildung: .blue
        case .fest: .mint
        case .sonstiges: .gray
        }
    }
}

extension City {
    var color: Color {
        switch self {
        case .mainz: Color(red: 0.80, green: 0.10, blue: 0.20)
        case .wiesbaden: Color(red: 0.10, green: 0.35, blue: 0.75)
        }
    }
}

struct CityBadge: View {
    let city: City

    var body: some View {
        Text(city.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(city.color)
            .background(city.color.opacity(0.12), in: Capsule())
    }
}
