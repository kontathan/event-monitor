import Foundation

/// Einheitliche Kategorien – unabhängig davon, wie die jeweilige Quelle ihre Termine einteilt.
public enum EventCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case markt
    case konzert
    case party
    case buehne
    case kino
    case ausstellung
    case fuehrung
    case kinder
    case sport
    case bildung
    case fest
    case sonstiges

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .markt: "Märkte & Flohmärkte"
        case .konzert: "Konzerte & Musik"
        case .party: "Party & Club"
        case .buehne: "Theater & Bühne"
        case .kino: "Kino & Film"
        case .ausstellung: "Ausstellungen"
        case .fuehrung: "Führungen"
        case .kinder: "Kinder & Familie"
        case .sport: "Sport & Bewegung"
        case .bildung: "Vorträge & Bildung"
        case .fest: "Feste"
        case .sonstiges: "Sonstiges"
        }
    }

    /// Name eines SF-Symbols für die Oberfläche.
    public var symbol: String {
        switch self {
        case .markt: "basket"
        case .konzert: "music.note"
        case .party: "figure.dance"
        case .buehne: "theatermasks"
        case .kino: "film"
        case .ausstellung: "photo.artframe"
        case .fuehrung: "figure.walk"
        case .kinder: "figure.and.child.holdinghands"
        case .sport: "figure.run"
        case .bildung: "book"
        case .fest: "party.popper"
        case .sonstiges: "calendar"
        }
    }
}

/// Ordnet Termine anhand von Stichwörtern einer Kategorie zu.
///
/// Geprüft wird zuerst die Kategorie der Quelle („kicker“), dann der Titel, dann der Text.
/// Innerhalb eines Feldes gewinnt die erste passende Kategorie in `rules`.
public enum Categorizer {
    /// Stichwörter sind bereits „gefaltet“ (klein, ohne Umlaute).
    /// Ein führendes `^` bedeutet: Das Wort muss mit dem Stichwort *beginnen*
    /// (verhindert z. B., dass „Aufführung“ als „Führung“ erkannt wird).
    static let rules: [(EventCategory, [String])] = [
        (.markt, ["flohmarkt", "trodel", "basar", "bazar", "markt", "kleiderborse", "spielzeugborse"]),
        (.kino, ["kino", "^film", "screening", "cinema"]),
        (.konzert, ["konzert", "orchester", "^chor", "jazz", "musik", "sinfoni", "symphoni", "liederabend",
                    "^band", "klavier", "orgel", "^gitarre", "^rock", "hip hop", "hiphop", "songwriter",
                    "unplugged", "acoustic"]),
        (.party, ["party", "^club", "^dj", "disco", "^rave", "techno", "clubnacht", "tanznacht"]),
        (.buehne, ["theater", "kabarett", "comedy", "kleinkunst", "^oper", "ballett", "musical", "^impro",
                   "variete", "poetry", "^slam", "^tanz", "schauspiel", "auffuhrung", "zauber", "^magie"]),
        (.fuehrung, ["^fuhrung", "stadtfuhrung", "themenfuhrung", "domfuhrung", "weinfuhrung", "rundgang",
                     "weinprobe", "besichtigung", "erlebnistour"]),
        (.ausstellung, ["ausstellung", "museum", "galerie", "vernissage", "finissage", "exhibition"]),
        (.kinder, ["kinder", "^kind", "familie", "jugend", "^kita"]),
        (.sport, ["sport", "^lauf", "yoga", "gymnastik", "qigong", "fitness", "wanderung", "^radtour",
                  "^turnier", "schwimm", "pilates", "zumba", "fussball", "marathon"]),
        (.bildung, ["vortrag", "vortrage", "lesung", "literatur", "seminar", "workshop", "^kurs", "studium",
                    "studiengang", "diskussion", "podium", "webinar", "fortbildung", "weiterbildung",
                    "infoabend", "infotag", "informationsveranstaltung", "beratung"]),
        (.fest, ["^fest", "festival", "^feier", "fastnacht", "fassenacht", "^kerb", "weinfest", "sommerfest",
                 "stadtfest", "herbstfest", "strassenfest", "hoffest", "oktoberfest", "^gala", "^umzug"])
    ]

    /// Quellen-Kategorien ohne Aussagekraft.
    static let meaninglessKickers: Set<String> = ["veranstaltungskalender", "sonstiges"]

    public static func category(kicker: String?, title: String, text: String?) -> EventCategory {
        if let kicker, !meaninglessKickers.contains(kicker.searchFolded), let match = firstMatch(in: kicker) {
            return match
        }
        if let match = firstMatch(in: title) { return match }
        // Lange Beschreibungen enthalten viele Wörter („Arbeitsmarkt“, „Musikschule“ …),
        // daher dort nur Wortanfänge vergleichen.
        if let text, let match = firstMatch(in: text, wordStartsOnly: true) { return match }
        return .sonstiges
    }

    static func firstMatch(in field: String, wordStartsOnly: Bool = false) -> EventCategory? {
        let folded = field.searchFolded
        let words = folded.split { !$0.isLetter && !$0.isNumber }
        for (category, keywords) in rules {
            for keyword in keywords {
                if keyword.hasPrefix("^") || wordStartsOnly {
                    let prefix = keyword.hasPrefix("^") ? keyword.dropFirst() : Substring(keyword)
                    if words.contains(where: { $0.hasPrefix(prefix) }) { return category }
                } else if folded.contains(keyword) {
                    return category
                }
            }
        }
        return nil
    }
}
