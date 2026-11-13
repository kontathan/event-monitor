import AppKit
import EventMonitorCore
import Foundation
import Observation

enum TimeFilter: String, CaseIterable, Identifiable {
    case all, today, tomorrow, weekend, week, twoWeeks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle Termine"
        case .today: "Heute"
        case .tomorrow: "Morgen"
        case .weekend: "Wochenende"
        case .week: "Nächste 7 Tage"
        case .twoWeeks: "Nächste 14 Tage"
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
        case .twoWeeks:
            return DateInterval(start: today, end: day(14))
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
    case interests
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

    /// Von Detailseiten nachgeladene Preise, je Veranstaltungsreihe (`seriesID`).
    private(set) var loadedPrices: [String: PriceInfo] = [:]
    private var priceRequests = Set<String>()
    private let priceLoader = DetailPriceLoader()
    private var pricesSaveScheduled = false

    init(store: JSONStore = .standard) {
        self.store = store
        settings = store.load(AppSettings.self, from: "settings.json") ?? AppSettings()
        if let cache = store.load(EventCache.self, from: "events.json") {
            // Kategorien neu bestimmen, falls sich die Stichwörter seit dem letzten Scan geändert haben.
            events = cache.events.map { $0.recategorized() }
            lastScan = cache.scannedAt
        }
        loadedPrices = store.load([String: PriceInfo].self, from: "prices.json") ?? [:]
        if !settings.interests.isEmpty { sidebarSelection = .interests }
    }

    // MARK: - Quellen & Scan

    var builtInSources: [SiteparkEventSource] { BuiltInSources.all }
    var recommendedSources: [ICalEventSource] { BuiltInSources.recommendedFeeds.map(ICalEventSource.init) }

    var activeSources: [any EventSource] {
        let disabled = settings.disabledSourceIDs
        let builtIns: [any EventSource] = builtInSources.filter { !disabled.contains($0.id) }
        let recommended: [any EventSource] = recommendedSources.filter { !disabled.contains($0.id) }
        let feeds: [any EventSource] = settings.customFeeds.filter(\.isEnabled).map(ICalEventSource.init)
        return builtIns + recommended + feeds
    }

    func sourceName(for id: String) -> String {
        let all: [any EventSource] = builtInSources + recommendedSources + settings.customFeeds.map(ICalEventSource.init)
        return all.first { $0.id == id }?.displayName ?? "Eigener Kalender"
    }

    func isSourceEnabled(_ id: String) -> Bool { !settings.disabledSourceIDs.contains(id) }

    func setSource(_ id: String, enabled: Bool) {
        if enabled { settings.disabledSourceIDs.remove(id) } else { settings.disabledSourceIDs.insert(id) }
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
        // Neu hinzugekommene Quellen sollen sofort Termine liefern.
        let scannedSources = Set(events.map(\.sourceID))
        let hasNewSource = activeSources.contains { !scannedSources.contains($0.id) }
        if events.isEmpty || (settings.autoScanOnLaunch && (stale || hasNewSource)) {
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
        switch sidebarSelection {
        case .category(let category): return base.filter { $0.category == category }
        case .interests: return base.filter { settings.interests.contains($0.category) }
        case .all, nil: return base
        }
    }

    // MARK: - Meine Interessen

    func isInterest(_ category: EventCategory) -> Bool {
        settings.interests.contains(category)
    }

    func toggleInterest(_ category: EventCategory) {
        if settings.interests.contains(category) {
            settings.interests.remove(category)
            if settings.interests.isEmpty && sidebarSelection == .interests { sidebarSelection = .all }
        } else {
            settings.interests.insert(category)
        }
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

    // MARK: - Preise

    func price(for event: Event) -> PriceInfo? {
        event.price ?? loadedPrices[event.seriesID]
    }

    /// Lädt den Preis von der Detailseite, falls die Quelle ihn nicht direkt nennt (nur Stadtkalender).
    func loadPriceIfNeeded(for event: Event) async {
        let key = event.seriesID
        guard event.price == nil, loadedPrices[key] == nil, !priceRequests.contains(key),
              let url = event.url, builtInSources.contains(where: { $0.id == event.sourceID })
        else { return }
        priceRequests.insert(key)
        defer { priceRequests.remove(key) }
        guard let price = await priceLoader.price(from: url) else { return }
        loadedPrices[key] = price
        schedulePricesSave()
    }

    private func schedulePricesSave() {
        guard !pricesSaveScheduled else { return }
        pricesSaveScheduled = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            pricesSaveScheduled = false
            try? store.save(loadedPrices, to: "prices.json")
        }
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
