import EventMonitorCore
import SwiftUI

struct EventListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let groups = model.dayGroups

        Group {
            if groups.isEmpty {
                emptyState
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let rule = model.lastAddedRule { UndoBar(rule: rule) }
                StatusBar(count: groups.reduce(0) { $0 + $1.events.count })
            }
            .background(.bar)
        }
        .navigationTitle(navigationTitle)
    }

    private var navigationTitle: String {
        switch model.sidebarSelection {
        case .category(let category): category.title
        case .interests: "Meine Interessen"
        default: "Veranstaltungen"
        }
    }

    @ViewBuilder private var emptyState: some View {
        if model.isScanning && model.events.isEmpty {
            ProgressView("Veranstaltungen werden geladen …")
        } else if model.events.isEmpty {
            ContentUnavailableView {
                Label("Noch keine Veranstaltungen", systemImage: "calendar")
            } description: {
                Text("Lade die aktuellen Termine.")
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

struct EventRow: View {
    @Environment(AppModel.self) private var model
    let event: Event

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.isAllDay ? "–" : Fmt.time(event.start))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .lineLimit(2)
                Text(Fmt.place(event))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            PriceText(price: model.price(for: event))
        }
        .padding(.vertical, 3)
        .help(event.category.title)
        .task(id: event.id) { await model.loadPriceIfNeeded(for: event) }
    }
}

/// Einträge für Kontextmenü und „Ausschließen“-Menü.
struct ExcludeMenuItems: View {
    @Environment(AppModel.self) private var model
    let event: Event

    var body: some View {
        Button("Diese Veranstaltung ausblenden") {
            model.addRule(.series(of: event))
        }
        if let venue = event.venue {
            Button("Alles am Ort „\(venue)“ ausblenden") {
                model.addRule(.venue(venue))
            }
        }
        Button("Kategorie „\(event.category.title)“ ausblenden") {
            model.addRule(.category(event.category))
        }
        Divider()
        Button("Nach Stichwort ausblenden …") {
            model.exclusionDraft = ExclusionDraft(text: event.title)
        }
    }
}

struct UndoBar: View {
    @Environment(AppModel.self) private var model
    let rule: ExclusionRule

    var body: some View {
        HStack(spacing: 8) {
            Text("Ausgeblendet: \(rule.displayValue)")
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Rückgängig") { model.undoLastRule() }
                .buttonStyle(.link)
            Button {
                model.lastAddedRule = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Schließen")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Divider() }
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(count == 1 ? "1 Veranstaltung" : "\(count) Veranstaltungen")
            Spacer()
            if !model.failures.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(model.failures.map { "\($0.sourceName): \($0.message)" }.joined(separator: "\n"))
            }
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("Aktualisiere …")
            } else if let lastScan = model.lastScan {
                Text("Aktualisiert \(Fmt.relative(lastScan))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Divider() }
    }
}
