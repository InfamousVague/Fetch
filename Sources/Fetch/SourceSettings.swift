import Foundation

/// A user-added Torznab/Newznab indexer endpoint (the standard, neutral
/// indexer API — Prowlarr/Jackett/most trackers expose it). Fetch never
/// ships or scrapes specific sites; the user supplies the endpoint.
struct TorznabIndexer: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var url: String          // base or full ?t=search endpoint
    var apiKey: String
}

/// A user-added torrent RSS/Atom feed (distro releases, Academic Torrents
/// collections, Internet Archive feeds, a seedbox, CC labels, …).
struct FeedSource: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var url: String
}

struct SourceSettings: Codable {
    /// CatalogProvider.rawValue values the user has disabled.
    var disabledBuiltins: Set<String> = []
    /// Extra BitTorrent trackers appended to magnets Fetch adds.
    var trackers: [String] = []
    var torznab: [TorznabIndexer] = []
    var feeds: [FeedSource] = []

    private static var url: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fetch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sources.json")
    }

    static func load() -> SourceSettings {
        (try? JSONDecoder().decode(SourceSettings.self, from: Data(contentsOf: url)))
            ?? SourceSettings()
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { try? d.write(to: Self.url) }
    }
}

// MARK: - Runtime search-source list

enum SourceKind: Hashable {
    case builtin(CatalogProvider)
    case torznab(TorznabIndexer)
    case rss(FeedSource)
}

struct SearchSource: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: SourceKind
}

extension SourceSettings {
    /// Enabled built-ins (natural order) followed by user indexers/feeds.
    var searchSources: [SearchSource] {
        var out: [SearchSource] = []
        for p in CatalogProvider.allCases where !disabledBuiltins.contains(p.rawValue) {
            out.append(SearchSource(id: "builtin:\(p.rawValue)", name: p.rawValue, kind: .builtin(p)))
        }
        for t in torznab {
            out.append(SearchSource(id: "tz:\(t.id)", name: t.name.isEmpty ? "Indexer" : t.name,
                                    kind: .torznab(t)))
        }
        for f in feeds {
            out.append(SearchSource(id: "rss:\(f.id)", name: f.name.isEmpty ? "Feed" : f.name,
                                    kind: .rss(f)))
        }
        return out
    }
}
