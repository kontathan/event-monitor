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
                .navigationSplitViewColumnWidth(min: 360, ideal: 440)
        } detail: {
            if let event = model.selectedEvent {
                EventDetailView(event: event)
            } else {
                ContentUnavailableView(
                    "Keine Veranstaltung ausgewählt",
                    systemImage: "calendar",
                    description: Text("Wähle eine Veranstaltung aus der Liste.")
                )
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Titel, Ort oder Stichwort")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.scan() }
                } label: {
                    if model.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                    }
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
            Section("Übersicht") {
                Label("Alle Veranstaltungen", systemImage: "square.grid.2x2")
                    .badge(counts.values.reduce(0, +))
                    .tag(SidebarSelection.all)
            }
            Section("Kategorien") {
                ForEach(EventCategory.allCases) { category in
                    let count = counts[category, default: 0]
                    if count > 0 || model.sidebarSelection == .category(category) {
                        Label {
                            Text(category.title)
                        } icon: {
                            Image(systemName: category.symbol).foregroundStyle(category.color)
                        }
                        .badge(count)
                        .tag(SidebarSelection.category(category))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
