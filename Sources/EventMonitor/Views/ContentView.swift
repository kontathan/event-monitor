import EventMonitorCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } content: {
            EventListView()
                .navigationSplitViewColumnWidth(min: 380, ideal: 460)
        } detail: {
            if let event = model.selectedEvent {
                EventDetailView(event: event)
            } else {
                ContentUnavailableView("Keine Auswahl", systemImage: "calendar",
                                       description: Text("Wähle eine Veranstaltung aus."))
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Suchen")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Stadt", selection: $model.cityFilter) {
                    Text("Alle").tag(City?.none)
                    ForEach(City.allCases) { city in
                        Text(city.displayName).tag(City?.some(city))
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .help("Nach Stadt filtern")
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("Zeitraum", selection: $model.timeFilter) {
                    ForEach(TimeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("Zeitraum wählen")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)
                .help("Alle Quellen neu abfragen (⌘R)")
            }
        }
        .sheet(item: $model.exclusionDraft) { draft in
            ExclusionDraftSheet(draft: draft)
        }
        .task { await model.scanOnLaunchIfNeeded() }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let counts = model.categoryCounts

        List(selection: $model.sidebarSelection) {
            Section {
                Label("Alle", systemImage: "tray.full")
                    .badge(counts.values.reduce(0, +))
                    .tag(SidebarSelection.all)
                if !model.settings.interests.isEmpty {
                    Label("Meine Interessen", systemImage: "star")
                        .badge(model.settings.interests.reduce(0) { $0 + counts[$1, default: 0] })
                        .tag(SidebarSelection.interests)
                        .help(model.settings.interests.map(\.title).sorted().joined(separator: ", "))
                }
                // Demos haben einen festen Platz – auch wenn gerade keine angekündigt ist.
                Label {
                    Text("Demos")
                } icon: {
                    Image(systemName: EventCategory.demo.symbol).foregroundStyle(EventCategory.demo.color)
                }
                .badge(counts[.demo, default: 0])
                .tag(SidebarSelection.category(.demo))
                .help(EventCategory.demo.title)
            }

            Section("Kategorien") {
                ForEach(EventCategory.allCases.filter { $0 != .demo }) { category in
                    let count = counts[category, default: 0]
                    if count > 0 || model.sidebarSelection == .category(category) || model.isInterest(category) {
                        Label {
                            Text(category.title)
                        } icon: {
                            Image(systemName: category.symbol).foregroundStyle(category.color)
                        }
                        .badge(count)
                        .tag(SidebarSelection.category(category))
                        .contextMenu {
                            Button(model.isInterest(category) ? "Aus „Meine Interessen“ entfernen"
                                                              : "Zu „Meine Interessen“ hinzufügen") {
                                model.toggleInterest(category)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
