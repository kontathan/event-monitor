import AppKit
import EventMonitorCore
import Foundation
import Observation

enum TimeFilter: String, CaseIterable, Identifiable {
    case all, today, tomorrow, weekend, week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle Termine"
        case .today: "Heute"
        case .tomorrow: "Morgen"
        case .weekend: "Wochenende"
        case .week: "Nächste 7 Tage"
        }
    }

    func interval(now: Date, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        switch self {
        case .all:
            return nil
        case .today:
            return DateInterval(start: today, end: day(1))
        case .tomorrow:
            return DateInterval(start: day(1), end: day(2))
        case .week:
            return DateInterval(start: today, end: day(7))
        case .weekend:
            // Freitag 17 Uhr bis Sonntag Mitternacht. Weekday: 1 = So … 7 = Sa.
            let weekday = calendar.component(.weekday, from: today)
            let saturdayOffset = weekday == 1 ? -1 : 7 - weekday
            let saturday = day(saturdayOffset)
            let start = max(today, saturday.addingTimeInterval(-7 * 3600))
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 2, to: saturday)!)
        }
    }
}

enum SidebarSelection: Hashable {
    case all
    case category(EventCategory)
}

struct DayGroup: Identifiable {
    let day: Date
    let events: [Event]
    var id: Date { day }
}

/// Vorbelegung für den Dialog „Nach Stichwort ausschließen“.
struct ExclusionDraft: Identifiable {
    let id = UUID()
    var text: String
    var kind: ExclusionRule.Kind = .titleContains
}

@MainActor
@Observable
final class AppModel {
    private let store: JSONStore

    var settings: AppSettings {
        didSet { if settings != oldValue { persistSettings() } }
    }

    private(set) var events: [Event] = []
    private(set) var lastScan: Date?
    private(set) var isScanning = false
    private(set) var failures: [SourceFailure] = []

    // Filter der Oberfläche
    var cityFilter: City?
    var timeFilter: TimeFilter = .all
    var sidebarSelection: SidebarSelection? = .all
    var searchText = ""
    var selectedEventID: Event.ID?
    var exclusionDraft: ExclusionDraft?
    /// Kurze Rückmeldung nach einem Ausschluss (mit Rückgängig).
    var lastAddedRule: ExclusionRule?

    init(store: JSONStore = .standard) {
        self.store = store
        settings = store.load(AppSettings.self, from: "settings.json") ?? AppSettings()
        if let cache = store.load(EventCache.self, from: "events.json") {
            events = cache.events
            lastScan = cache.scannedAt
        }
    }

    // MARK: - Quellen & Scan

    var builtInSources: [SiteparkEventSource] { BuiltInSources.all }

    var activeSources: [any EventSource] {
        let builtIns: [any EventSource] = builtInSources.filter { !settings.disabledSourceIDs.contains($0.id) }
        let feeds: [any EventSource] = settings.customFeeds.filter(\.isEnabled).map(ICalEventSource.init)
        return builtIns + feeds
    }

    func sourceName(for id: String) -> String {
        activeSources.first { $0.id == id }?.displayName
            ?? builtInSources.first { $0.id == id }?.displayName
            ?? "Eigener Kalender"
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let scanner = EventScanner(sources: activeSources, rules: settings.exclusionRules, days: settings.scanDays)
        let result = await scanner.scan()

        // Falls eine Quelle ausfällt, behalten wir deren alte Termine statt sie zu verlieren.
        let failedIDs = Set(activeSources.filter { s in result.failures.contains { $0.sourceName == s.displayName } }.map(\.id))
        let kept = events.filter { failedIDs.contains($0.sourceID) }
        events = EventScanner.process(result.events + kept, rules: settings.exclusionRules, now: .now).events
        failures = result.failures
        lastScan = result.scannedAt
        if let selectedEventID, !events.contains(where: { $0.id == selectedEventID }) { self.selectedEventID = nil }
        try? store.save(EventCache(events: events, scannedAt: lastScan), to: "events.json")
    }

    func scanOnLaunchIfNeeded() async {
        let stale = lastScan.map { Date.now.timeIntervalSince($0) > 3 * 3600 } ?? true
        if events.isEmpty || (settings.autoScanOnLaunch && stale) {
            await scan()
        }
    }

    // MARK: - Ausschlüsse

    func addRule(_ rule: ExclusionRule) {
        guard !settings.exclusionRules.contains(where: { $0.kind == rule.kind && $0.value == rule.value }) else { return }
        settings.exclusionRules.append(rule)
        events.removeAll { rule.matches($0) }
        if let selectedEventID, !events.contains(where: { $0.id == selectedEventID }) { self.selectedEventID = nil }
        try? store.save(EventCache(events: events, scannedAt: lastScan), to: "events.json")
        lastAddedRule = rule
    }

    /// Entfernt Regeln und scannt neu, damit die Termine wieder erscheinen.
    func removeRules(_ ids: Set<ExclusionRule.ID>) {
        settings.exclusionRules.removeAll { ids.contains($0.id) }
        if lastAddedRule.map({ ids.contains($0.id) }) == true { lastAddedRule = nil }
        Task { await scan() }
    }

    func undoLastRule() {
        guard let rule = lastAddedRule else { return }
        removeRules([rule.id])
    }

    // MARK: - Gefilterte Ansicht

    private var calendar: Calendar { .current }

    /// Alle Filter außer der Kategorie – Grundlage für die Zähler in der Seitenleiste.
    private var eventsIgnoringCategory: [Event] {
        let now = Date.now
        let interval = timeFilter.interval(now: now, calendar: calendar)
        let query = searchText.trimmingCharacters(in: .whitespaces).searchFolded
        let rules = settings.exclusionRules
        return events.filter { event in
            if event.hasEnded(at: now) { return false }
            if let cityFilter, event.city != cityFilter { return false }
            if let interval, !event.overlaps(interval, calendar: calendar) { return false }
            if !query.isEmpty {
                let haystack = [event.title, event.venue ?? "", event.summary ?? "", event.sourceCategory ?? ""]
                    .joined(separator: " ").searchFolded
                if !query.split(separator: " ").allSatisfy({ haystack.contains($0) }) { return false }
            }
            return !rules.excludes(event)
        }
    }

    var visibleEvents: [Event] {
        let base = eventsIgnoringCategory
        guard case .category(let category) = sidebarSelection else { return base }
        return base.filter { $0.category == category }
    }

    var categoryCounts: [EventCategory: Int] {
        Dictionary(grouping: eventsIgnoringCategory, by: \.category).mapValues(\.count)
    }

    var dayGroups: [DayGroup] {
        let today = calendar.startOfDay(for: .now)
        let grouped = Dictionary(grouping: visibleEvents) { max(today, calendar.startOfDay(for: $0.start)) }
        return grouped.keys.sorted().map { DayGroup(day: $0, events: grouped[$0]!) }
    }

    var selectedEvent: Event? {
        selectedEventID.flatMap { id in events.first { $0.id == id } }
    }

    var hasActiveFilters: Bool {
        cityFilter != nil || timeFilter != .all || sidebarSelection != .all || !searchText.isEmpty
    }

    func resetFilters() {
        cityFilter = nil
        timeFilter = .all
        sidebarSelection = .all
        searchText = ""
    }

    // MARK: - Aktionen

    /// Exportiert den Termin als .ics und öffnet ihn mit der Standard-Kalender-App.
    func addToCalendar(_ event: Event) {
        let safeName = event.title.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.prefix(6).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appending(path: "\(safeName.isEmpty ? "Termin" : safeName).ics")
        do {
            try ICalendar.export([event]).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }

    /// Kartensuche bei OpenStreetMap (offen und ohne Konto).
    func mapURL(for event: Event) -> URL? {
        guard let venue = event.venue else { return nil }
        var components = URLComponents(string: "https://www.openstreetmap.org/search")!
        components.queryItems = [URLQueryItem(name: "query", value: "\(venue), \(event.city.displayName)")]
        return components.url
    }

    func revealDataFolder() {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([store.directory])
    }

    private func persistSettings() {
        try? store.save(settings, to: "settings.json")
    }
}
