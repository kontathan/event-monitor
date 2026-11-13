import EventMonitorCore
import SwiftUI

struct EventListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let groups = model.dayGroups

        VStack(spacing: 0) {
            FilterBar()
            Divider()

            if groups.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selectedEventID) {
                    ForEach(groups) { group in
                        Section(Fmt.dayHeader(group.day)) {
                            ForEach(group.events) { event in
                                EventRow(event: event)
                                    .tag(event.id)
                                    .contextMenu { ExcludeMenuItems(event: event) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            if let rule = model.lastAddedRule {
                Divider()
                UndoBanner(rule: rule)
            }
            Divider()
            StatusBar(count: groups.reduce(0) { $0 + $1.events.count })
        }
    }

    @ViewBuilder private var emptyState: some View {
        if model.isScanning && model.events.isEmpty {
            ProgressView("Veranstaltungen werden geladen …")
        } else if model.events.isEmpty {
            ContentUnavailableView {
                Label("Noch keine Veranstaltungen", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("Lade die aktuellen Termine aus Mainz und Wiesbaden.")
            } actions: {
                Button("Jetzt laden") { Task { await model.scan() } }
            }
        } else {
            ContentUnavailableView {
                Label("Keine Treffer", systemImage: "magnifyingglass")
            } description: {
                Text("Für diese Filter gibt es keine Veranstaltungen.")
            } actions: {
                if model.hasActiveFilters { Button("Filter zurücksetzen") { model.resetFilters() } }
            }
        }
    }
}

struct FilterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            Picker("Stadt", selection: $model.cityFilter) {
                Text("Beide Städte").tag(City?.none)
                ForEach(City.allCases) { city in
                    Text(city.displayName).tag(City?.some(city))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("Zeitraum", selection: $model.timeFilter) {
                ForEach(TimeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct EventRow: View {
    let event: Event

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(event.isAllDay ? "ganzt." : Fmt.time(event.start))
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(event.isAllDay ? .secondary : .primary)
                .frame(width: 48, alignment: .trailing)

            Image(systemName: event.category.symbol)
                .foregroundStyle(event.category.color)
                .frame(width: 18)
                .help(event.category.title)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    CityBadge(city: event.city)
                    if let venue = event.venue {
                        Text(venue)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Einträge für Kontextmenü und „Ausschließen“-Knopf.
struct ExcludeMenuItems: View {
    @Environment(AppModel.self) private var model
    let event: Event

    var body: some View {
        Button("Diese Veranstaltung ausschließen (alle Termine)") {
            model.addRule(.series(of: event))
        }
        if let venue = event.venue {
            Button("Alles am Ort „\(venue)“ ausschließen") {
                model.addRule(.venue(venue))
            }
        }
        Button("Kategorie „\(event.category.title)“ ausschließen") {
            model.addRule(.category(event.category))
        }
        Divider()
        Button("Nach Stichwort ausschließen …") {
            model.exclusionDraft = ExclusionDraft(text: event.title)
        }
    }
}

struct UndoBanner: View {
    @Environment(AppModel.self) private var model
    let rule: ExclusionRule

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
            Text("Ausgeschlossen: \(rule.kind.title) „\(rule.displayValue)“")
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Rückgängig") { model.undoLastRule() }
            Button {
                model.lastAddedRule = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Hinweis schließen")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.12))
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(count == 1 ? "1 Veranstaltung" : "\(count) Veranstaltungen")
            Spacer()
            if !model.failures.isEmpty {
                Label("\(model.failures.count) Quelle(n) nicht erreichbar", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(model.failures.map { "\($0.sourceName): \($0.message)" }.joined(separator: "\n"))
            }
            if model.isScanning {
                Text("Wird aktualisiert …")
            } else if let lastScan = model.lastScan {
                Text("Aktualisiert \(Fmt.relative(lastScan))")
                    .help(Fmt.longDate(lastScan) + ", " + Fmt.time(lastScan) + " Uhr")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}
