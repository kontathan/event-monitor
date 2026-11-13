import EventMonitorCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ExclusionSettingsView()
                .tabItem { Label("Ausschlüsse", systemImage: "eye.slash") }
            SourcesSettingsView()
                .tabItem { Label("Quellen", systemImage: "antenna.radiowaves.left.and.right") }
            GeneralSettingsView()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
        }
        .frame(width: 620, height: 560)
    }
}

// MARK: - Ausschlüsse

struct ExclusionSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<ExclusionRule.ID>()
    @State private var newKeyword = ""
    @State private var newKind: ExclusionRule.Kind = .titleContains

    var body: some View {
        let rules = model.settings.exclusionRules.sorted { $0.createdAt > $1.createdAt }

        VStack(alignment: .leading, spacing: 12) {
            Text("Diese Veranstaltungen werden bei jedem Scan herausgefiltert. Entfernst du eine Regel, wird automatisch neu gescannt.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if rules.isEmpty {
                ContentUnavailableView(
                    "Keine Ausschlüsse",
                    systemImage: "eye",
                    description: Text("Rechtsklick auf eine Veranstaltung → „Ausschließen“.")
                )
                .frame(maxHeight: .infinity)
            } else {
                Table(rules, selection: $selection) {
                    TableColumn("Art") { Text($0.kind.title).foregroundStyle(.secondary) }
                        .width(min: 90, ideal: 110, max: 140)
                    TableColumn("Wert") { Text($0.displayValue) }
                    TableColumn("Seit") { Text($0.createdAt.formatted(date: .numeric, time: .omitted)) }
                        .width(min: 70, ideal: 80, max: 100)
                }
                .contextMenu(forSelectionType: ExclusionRule.ID.self) { ids in
                    Button("Entfernen", role: .destructive) { model.removeRules(ids) }
                }
                .onDeleteCommand { model.removeRules(selection); selection = [] }

                HStack {
                    Button("Ausgewählte entfernen", role: .destructive) {
                        model.removeRules(selection)
                        selection = []
                    }
                    .disabled(selection.isEmpty)
                    Spacer()
                    Text("\(rules.count) Regel(n)").foregroundStyle(.secondary)
                }
            }

            GroupBox("Neues Stichwort") {
                HStack {
                    Picker("", selection: $newKind) {
                        Text("Titel enthält").tag(ExclusionRule.Kind.titleContains)
                        Text("Ort enthält").tag(ExclusionRule.Kind.venueContains)
                    }
                    .labelsHidden()
                    .fixedSize()
                    TextField("z. B. Gymnastik", text: $newKeyword)
                        .onSubmit(addKeyword)
                    Button("Hinzufügen", action: addKeyword)
                        .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(4)
            }
        }
        .padding(20)
    }

    private func addKeyword() {
        let text = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        model.addRule(ExclusionRule(kind: newKind, value: text))
        newKeyword = ""
    }
}

// MARK: - Quellen

struct SourcesSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var feedName = ""
    @State private var feedURL = ""
    @State private var feedCity: City = .mainz

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                ForEach(model.builtInSources, id: \.id) { source in
                    Toggle(isOn: builtInBinding(source.id)) {
                        VStack(alignment: .leading) {
                            Text(source.displayName)
                            Text(source.baseURL.host() ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Offizielle Stadtkalender")
            }

            Section {
                ForEach(model.recommendedSources, id: \.id) { source in
                    Toggle(isOn: builtInBinding(source.id)) {
                        VStack(alignment: .leading) {
                            Text(source.displayName)
                            Text("\(source.city.displayName) · \(source.feed.url.host() ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Empfohlene Orte")
            } footer: {
                Text("Kulturorte mit offenem Kalender, die direkt eingelesen werden.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach($model.settings.customFeeds) { $feed in
                    HStack {
                        Toggle("", isOn: $feed.isEnabled).labelsHidden()
                        VStack(alignment: .leading) {
                            Text(feed.name)
                            Text(feed.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(feed.city.displayName).foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            model.settings.customFeeds.removeAll { $0.id == feed.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                TextField("Name", text: $feedName, prompt: Text("z. B. Lieblingsclub"))
                TextField("Adresse", text: $feedURL, prompt: Text("iCal-Feed oder Webseite"))
                Picker("Stadt", selection: $feedCity) {
                    ForEach(City.allCases) { Text($0.displayName).tag($0) }
                }
                HStack {
                    Spacer()
                    Button("Kalender hinzufügen", action: addFeed)
                        .disabled(ICalFeed.normalizedURL(from: feedURL) == nil)
                }
            } header: {
                Text("Eigene Kalender & Webseiten")
            } footer: {
                Text("Unterstützt iCal-Feeds (.ics, webcal://) und Webseiten mit eingebetteten schema.org-Veranstaltungsdaten. Änderungen gelten ab dem nächsten Scan (⌘R).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func builtInBinding(_ id: String) -> Binding<Bool> {
        Binding { model.isSourceEnabled(id) } set: { model.setSource(id, enabled: $0) }
    }

    private func addFeed() {
        guard let url = ICalFeed.normalizedURL(from: feedURL) else { return }
        let name = feedName.trimmingCharacters(in: .whitespaces)
        model.settings.customFeeds.append(ICalFeed(name: name.isEmpty ? (url.host() ?? "Kalender") : name, url: url, city: feedCity))
        feedName = ""
        feedURL = ""
    }
}

// MARK: - Allgemein

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(EventCategory.allCases) { category in
                        Toggle(isOn: Binding(get: { model.isInterest(category) },
                                             set: { _ in model.toggleInterest(category) })) {
                            Label(category.title, systemImage: category.symbol)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            } header: {
                Text("Meine Interessen")
            } footer: {
                Text("Diese Kategorien erscheinen in der Seitenleiste gesammelt unter „Meine Interessen“.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Vorschau-Zeitraum", selection: $model.settings.scanDays) {
                Text("14 Tage").tag(14)
                Text("30 Tage").tag(30)
                Text("60 Tage").tag(60)
                Text("90 Tage").tag(90)
            }
            Toggle("Beim Start automatisch aktualisieren", isOn: $model.settings.autoScanOnLaunch)
            LabeledContent("Gespeicherte Daten") {
                Button("Im Finder zeigen") { model.revealDataFolder() }
            }
            Text("Einstellungen und Ausschlüsse liegen als lesbare JSON-Dateien im Ordner „Application Support/EventMonitor“.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
