import EventMonitorCore
import SwiftUI

struct EventDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let event: Event

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Label(event.category.title, systemImage: event.category.symbol)
                        .foregroundStyle(event.category.color)
                        .font(.callout.weight(.semibold))
                    CityBadge(city: event.city)
                }

                Text(event.title)
                    .font(.largeTitle.weight(.bold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                    infoRow("calendar", Fmt.longDate(event.start))
                    infoRow("clock", Fmt.timeRange(event))
                    if let venue = event.venue {
                        infoRow("mappin.and.ellipse", "\(venue), \(event.city.displayName)")
                    }
                    if let source = event.sourceCategory {
                        infoRow("tag", source)
                    }
                }
                .font(.title3)

                actions

                if let summary = event.summary {
                    Divider()
                    Text(summary)
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if summary.hasSuffix("…") || summary.hasSuffix("...") {
                        Text("Gekürzt – die vollständige Beschreibung steht auf der Website.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                Text("Quelle: \(model.sourceName(for: event.sourceID)). Alle Angaben ohne Gewähr – bitte beim Veranstalter prüfen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if let url = event.url {
                Button {
                    openURL(url)
                } label: {
                    Label("Zur Website", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
            }
            Button {
                model.addToCalendar(event)
            } label: {
                Label("In Kalender", systemImage: "calendar.badge.plus")
            }
            .help("Als .ics-Datei exportieren und in der Kalender-App öffnen")
            if let mapURL = model.mapURL(for: event) {
                Button {
                    openURL(mapURL)
                } label: {
                    Label("Karte", systemImage: "map")
                }
                .help("Ort bei OpenStreetMap suchen")
            }
            Menu {
                ExcludeMenuItems(event: event)
            } label: {
                Label("Ausschließen", systemImage: "eye.slash")
            }
            .fixedSize()
            .help("Diese oder ähnliche Veranstaltungen künftig nicht mehr anzeigen")
        }
        .controlSize(.large)
    }

    private func infoRow(_ symbol: String, _ text: String) -> some View {
        GridRow {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(text).textSelection(.enabled)
        }
    }
}

/// Dialog: eigenes Stichwort für einen Ausschluss eingeben.
struct ExclusionDraftSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: ExclusionDraft

    private var trimmed: String { draft.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nach Stichwort ausschließen")
                .font(.title2.weight(.semibold))
            Text("Alle Veranstaltungen, deren Titel bzw. Ort dieses Stichwort enthält, werden ab sofort und bei künftigen Scans ausgeblendet. Groß-/Kleinschreibung und Umlaute spielen keine Rolle.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Prüfen in", selection: $draft.kind) {
                Text("Titel").tag(ExclusionRule.Kind.titleContains)
                Text("Ort").tag(ExclusionRule.Kind.venueContains)
            }
            .pickerStyle(.segmented)

            TextField("Stichwort, z. B. „Wochenmarkt“", text: $draft.text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            let matches = model.events.filter { ExclusionRule(kind: draft.kind, value: trimmed).matches($0) }.count
            Text(trimmed.isEmpty ? " " : "Betrifft aktuell \(matches) Termin(e).")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Ausschließen", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        model.addRule(ExclusionRule(kind: draft.kind, value: trimmed))
        dismiss()
    }
}
