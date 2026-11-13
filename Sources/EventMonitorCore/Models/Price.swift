import Foundation

/// Eintrittspreis einer Veranstaltung, so gut er sich aus den Quellen ablesen lässt.
public struct PriceInfo: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case free
        case paid
        case donation
        /// Geprüft, aber keine Angabe gefunden.
        case unknown
    }

    public var kind: Kind
    public var min: Double?
    public var max: Double?

    public init(kind: Kind, min: Double? = nil, max: Double? = nil) {
        self.kind = kind
        self.min = min
        self.max = max
    }

    public static let free = PriceInfo(kind: .free)
    public static let donation = PriceInfo(kind: .donation)
    public static let unknown = PriceInfo(kind: .unknown)

    public static func paid(_ amounts: [Double]) -> PriceInfo {
        PriceInfo(kind: .paid, min: amounts.min(), max: amounts.max())
    }

    /// Kurzer Text für die Oberfläche, z. B. „Kostenlos“, „12 €“, „8–15 €“.
    public var label: String? {
        switch kind {
        case .free: return "Kostenlos"
        case .donation: return "Spende"
        case .unknown: return nil
        case .paid:
            guard let min else { return nil }
            guard let max, max > min else { return Self.euro(min) }
            return "\(Self.euro(min).dropLast(2))–\(Self.euro(max))"
        }
    }

    static func euro(_ value: Double) -> String {
        if value == value.rounded() { return "\(Int(value)) €" }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",") + " €"
    }
}

/// Liest Preisangaben aus Freitext („Eintritt frei“, „VVK 12 €, AK 15 €“ …).
public enum PriceParser {
    static let freePhrases = [
        "eintritt frei", "eintritt ist frei", "freier eintritt", "eintritt: frei", "eintritt kostenlos",
        "eintritt: kostenlos", "kostenlos", "kostenfrei", "gebuhrenfrei", "entgeltfrei", "free entry",
        "free admission", "umsonst", "ohne eintritt", "teilnahme frei", "eintritt: 0"
    ]
    static let donationPhrases = [
        "spende", "hutsammlung", "hut geht", "pay what you", "solibeitrag", "soli-beitrag", "auf spendenbasis"
    ]

    public static func parse(_ text: String?) -> PriceInfo? {
        guard let text, !text.isEmpty else { return nil }
        let folded = text.searchFolded
        let amounts = euroAmounts(in: folded).filter { $0 > 0 && $0 < 1000 }
        if !amounts.isEmpty { return .paid(amounts) }
        if freePhrases.contains(where: folded.contains) { return .free }
        if donationPhrases.contains(where: folded.contains) { return .donation }
        return nil
    }

    /// Findet Beträge wie „12 €“, „3,99 €“, „€ 8“, „15 Euro“, „10 EUR“.
    static func euroAmounts(in text: String) -> [Double] {
        let number = #"(\d{1,4}(?:[.,]\d{1,2})?)"#
        let patterns = [number + #"\s*(?:€|euro\b|eur\b)"#, #"(?:€|eur)\s*"# + number]
        var result: [Double] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let r = Range(match.range(at: 1), in: text) else { continue }
                let value = Double(text[r].replacingOccurrences(of: ",", with: "."))
                if let value { result.append(value) }
            }
        }
        return result
    }

    /// Sucht auf einer Detailseite (HTML) den Abschnitt zum Eintritt und liest den Preis daraus.
    public static func fromDetailPage(_ html: String) -> PriceInfo {
        let text = HTMLText.plain(html).searchFolded
        for marker in ["eintritt und preise", "eintritt:", "eintritt", "preise", "kosten"] {
            guard let range = text.range(of: marker) else { continue }
            var section = String(text[range.lowerBound...].prefix(400))
            if let end = section.range(of: "veranstaltungsort") { section = String(section[..<end.lowerBound]) }
            if let price = parse(section) { return price }
        }
        return .unknown
    }
}

/// Minimaler HTML-zu-Text-Wandler (ohne Abhängigkeiten).
enum HTMLText {
    static func plain(_ html: String) -> String {
        var text = html
        for pattern in [#"<script[\s\S]*?</script>"#, #"<style[\s\S]*?</style>"#, #"<[^>]+>"#] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return decodeEntities(text)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func decodeEntities(_ text: String) -> String {
        var result = text
        let entities = ["&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#039;": "'", "&#39;": "'", "&apos;": "'",
                        "&lt;": "<", "&gt;": ">", "&euro;": "€", "&#8364;": "€", "&ndash;": "–", "&#8211;": "–",
                        "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü",
                        "&szlig;": "ß", "&#8217;": "’", "&hellip;": "…"]
        for (entity, replacement) in entities { result = result.replacingOccurrences(of: entity, with: replacement) }
        return result
    }
}

/// Lädt Preise von den Detailseiten der Stadtkalender nach – höflich: höchstens drei gleichzeitig,
/// und nur für Termine, die tatsächlich angezeigt werden.
public actor DetailPriceLoader {
    private let client: any HTTPClient
    private let maxConcurrent: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(client: any HTTPClient = URLSession.shared, maxConcurrent: Int = 3) {
        self.client = client
        self.maxConcurrent = maxConcurrent
    }

    /// `nil`, wenn die Anfrage abgebrochen wurde oder fehlschlug (dann später erneut versuchen).
    public func price(from url: URL) async -> PriceInfo? {
        await acquire()
        defer { release() }
        guard !Task.isCancelled else { return nil }
        guard let data = try? HTTP.checked(try await client.fetch(HTTP.request(url))) else { return nil }
        return PriceParser.fromDetailPage(String(decoding: data, as: UTF8.self))
    }

    private func acquire() async {
        if running < maxConcurrent { running += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
    }
}
