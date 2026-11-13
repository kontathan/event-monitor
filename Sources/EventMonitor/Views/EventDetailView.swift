import EventMonitorCore
import SwiftUI

struct EventDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let event: Event

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(event.category.title, systemImage: event.category.symbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(event.category.color)
                    Text(event.title)
                        .font(.title.weight(.semibold))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    InfoRow(symbol: "calendar", text: Fmt.longDate(event.start))
                    InfoRow(symbol: "clock", text: Fmt.timeRange(event))
                    InfoRow(symbol: "mappin.and.ellipse", text: Fmt.place(event))
                    InfoRow(symbol: "eurosign", text: priceText, highlight: model.price(for: event)?.kind == .free)
                }

                actions

                if let summary = event.summary {
                    Text(summary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Quelle: \(model.sourceName(for: event.sourceID)) · Angaben ohne Gewähr")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(32)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: event.id) { await model.loadPriceIfNeeded(for: event) }
    }

    private var priceText: String {
        if let label = model.price(for: event)?.label { return label }
        if model.price(for: event)?.kind == .unknown || !isCityCalendar { return "Keine Preisangabe" }
        return "Preis wird geladen …"
    }

    private var isCityCalendar: Bool {
        model.builtInSources.contains { $0.id == event.sourceID }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let url = event.url {
                Button("Website") { openURL(url) }
                    .buttonStyle(.borderedProminent)
            }
            Button("Zum Kalender") { model.addToCalendar(event) }
                .help("Als .ics-Datei in der Kalender-App öffnen")
            if let mapURL = model.mapURL(for: event) {
                Button("Karte") { openURL(mapURL) }
                    .help("Ort bei OpenStreetMap zeigen")
            }
            Spacer()
            Menu {
                ExcludeMenuItems(event: event)
            } label: {
                Image(systemName: "eye.slash")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Ausblenden …")
        }
    }
}

private struct InfoRow: View {
    let symbol: String
    let text: String
    var highlight = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .foregroundStyle(highlight ? Color.green : Color.primary)
                .textSelection(.enabled)
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
        Form {
            Section {
                Picker("Suchen in", selection: $draft.kind) {
                    Text("Titel").tag(ExclusionRule.Kind.titleContains)
                    Text("Ort").tag(ExclusionRule.Kind.venueContains)
                }
                .pickerStyle(.segmented)
                TextField("Stichwort", text: $draft.text, prompt: Text("z. B. Wochenmarkt"))
                    .onSubmit(save)
            } header: {
                Text("Nach Stichwort ausblenden")
            } footer: {
                let matches = model.events.filter { ExclusionRule(kind: draft.kind, value: trimmed).matches($0) }.count
                Text(trimmed.isEmpty ? "Gilt ab sofort und für alle künftigen Scans."
                                     : "Betrifft aktuell \(matches) Termin(e). Gilt auch für künftige Scans.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Ausblenden", action: save).disabled(trimmed.isEmpty)
            }
        }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        model.addRule(ExclusionRule(kind: draft.kind, value: trimmed))
        dismiss()
    }
}
