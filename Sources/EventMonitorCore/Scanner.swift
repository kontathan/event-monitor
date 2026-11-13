import Foundation

public struct SourceFailure: Hashable, Sendable {
    public var sourceName: String
    public var message: String
}

public struct ScanResult: Sendable {
    public var events: [Event]
    public var failures: [SourceFailure]
    /// Wie viele Termine durch Ausschlussregeln herausgefiltert wurden.
    public var excludedCount: Int
    public var scannedAt: Date
}

/// Fragt alle Quellen parallel ab, entfernt Doppelte, Vergangenes und Ausgeschlossenes.
public struct EventScanner: Sendable {
    public var sources: [any EventSource]
    public var rules: [ExclusionRule]
    public var days: Int
    public var client: any HTTPClient

    public init(sources: [any EventSource], rules: [ExclusionRule], days: Int,
                client: any HTTPClient = URLSession.shared) {
        self.sources = sources
        self.rules = rules
        self.days = days
        self.client = client
    }

    public func scan(now: Date = .now) async -> ScanResult {
        let days = days
        let client = client
        var collected: [Event] = []
        var failures: [SourceFailure] = []

        await withTaskGroup(of: (String, Result<[Event], any Error>).self) { group in
            for source in sources {
                group.addTask {
                    do { return (source.displayName, .success(try await source.fetchEvents(days: days, client: client))) }
                    catch { return (source.displayName, .failure(error)) }
                }
            }
            for await (name, result) in group {
                switch result {
                case .success(let events): collected += events
                case .failure(let error): failures.append(SourceFailure(sourceName: name, message: error.localizedDescription))
                }
            }
        }

        let filtered = Self.process(collected, rules: rules, now: now)
        return ScanResult(events: filtered.events, failures: failures.sorted { $0.sourceName < $1.sourceName },
                          excludedCount: filtered.excluded, scannedAt: now)
    }

    /// Reine Funktion – gut testbar.
    public static func process(_ events: [Event], rules: [ExclusionRule], now: Date) -> (events: [Event], excluded: Int) {
        var seen = Set<String>()
        var result: [Event] = []
        var excluded = 0
        for event in events where !event.hasEnded(at: now) && seen.insert(event.id).inserted {
            if rules.excludes(event) { excluded += 1; continue }
            result.append(event)
        }
        result.sort { ($0.start, $0.title) < ($1.start, $1.title) }
        return (result, excluded)
    }
}

/// Speichert Einstellungen und Zwischenspeicher als JSON in „Application Support“.
public struct JSONStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static var standard: JSONStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return JSONStore(directory: base.appending(path: "EventMonitor", directoryHint: .isDirectory))
    }

    public func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    public func save<T: Encodable>(_ value: T, to name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: directory.appending(path: name), options: .atomic)
    }
}
