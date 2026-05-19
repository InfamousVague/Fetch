import Foundation

/// Legal sources only. Each provider's legitimacy is guaranteed by the
/// source itself (authoritative catalog / official publisher), never by
/// trying to filter an indiscriminate piracy index.
enum CatalogProvider: String, CaseIterable, Identifiable {
    case internetArchive = "Archive"
    case freeMedia       = "Free media"
    case distros         = "Linux/BSD"
    case academic        = "Academic"
    var id: String { rawValue }
}

enum TorrentRef: Hashable {
    case torrentURL(URL)
    case magnet(String)
}

struct CatalogResult: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let ref: TorrentRef
}

enum Catalog {
    static func search(_ provider: CatalogProvider, _ query: String) async throws -> [CatalogResult] {
        switch provider {
        case .internetArchive: return try await ia(query, collections: nil)
        case .freeMedia:
            return try await ia(query, collections:
                ["librivoxaudio", "gutenberg", "opensource_movies", "prelinger", "blender"])
        case .distros:  return filter(distros, query)
        case .academic: return try await academic(query)
        }
    }

    /// Dispatch for any search source (built-in or user-added indexer/feed).
    static func search(_ source: SearchSource, _ query: String) async throws -> [CatalogResult] {
        switch source.kind {
        case .builtin(let p): return try await search(p, query)
        case .torznab(let t): return try await torznab(t, query)
        case .rss(let f):     return try await feed(f, query)
        }
    }

    /// Append user-configured trackers to a magnet link.
    static func withTrackers(_ magnet: String, _ trackers: [String]) -> String {
        guard magnet.hasPrefix("magnet:"), !trackers.isEmpty else { return magnet }
        let extra = trackers
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) }
            .map { "&tr=\($0)" }
            .joined()
        return magnet + extra
    }

    // MARK: User-added Torznab / Newznab indexer (standard neutral API)

    private static func torznab(_ tz: TorznabIndexer, _ query: String) async throws -> [CatalogResult] {
        guard var c = URLComponents(string: tz.url) else { return [] }
        var items = c.queryItems ?? []
        func setItem(_ n: String, _ v: String) {
            items.removeAll { $0.name == n }; items.append(.init(name: n, value: v))
        }
        if items.first(where: { $0.name == "t" }) == nil { setItem("t", "search") }
        setItem("q", query)
        if !tz.apiKey.isEmpty { setItem("apikey", tz.apiKey) }
        c.queryItems = items
        guard let url = c.url else { return [] }
        var req = URLRequest(url: url); req.timeoutInterval = 15
        req.setValue("Fetch/0.1", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return parseItems(String(decoding: data, as: UTF8.self), prefix: tz.name)
    }

    // MARK: User-added RSS / Atom torrent feed

    private static func feed(_ f: FeedSource, _ query: String) async throws -> [CatalogResult] {
        guard let url = URL(string: f.url) else { return [] }
        var req = URLRequest(url: url); req.timeoutInterval = 15
        req.setValue("Fetch/0.1", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        let all = parseItems(String(decoding: data, as: UTF8.self), prefix: f.name)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? all : all.filter { $0.title.lowercased().contains(q) }
    }

    /// Tolerant RSS2/Atom/Torznab item extraction (no XML lib / no deps).
    private static func parseItems(_ xml: String, prefix: String) -> [CatalogResult] {
        var blocks: [String] = []
        for tag in ["item", "entry"] {
            let re = try? NSRegularExpression(pattern: "<\(tag)[ >][\\s\\S]*?</\(tag)>",
                                              options: [.caseInsensitive])
            re?.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).forEach {
                if let r = Range($0.range, in: xml) { blocks.append(String(xml[r])) }
            }
        }
        var seen = Set<String>(); var out: [CatalogResult] = []
        for b in blocks {
            let title = firstGroup(b, "<title[^>]*>(?:<!\\[CDATA\\[)?([\\s\\S]*?)(?:\\]\\]>)?</title>")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled"
            var ref: TorrentRef?
            if let mag = firstMatch(b, "magnet:\\?xt=urn:btih:[^\"'&<\\s]+[^\"'<\\s]*") {
                ref = .magnet(mag)
            } else if let enc = firstGroup(b, "<enclosure[^>]*url=\"([^\"]+)\"") {
                ref = enc.hasPrefix("magnet:") ? .magnet(enc)
                    : (URL(string: enc).map { TorrentRef.torrentURL($0) })
            } else if let ih = firstGroup(b, "name=\"infohash\"\\s+value=\"([0-9a-fA-F]{40})\""),
                      let enc = ih.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
                ref = .magnet("magnet:?xt=urn:btih:\(enc)")
            }
            guard let r = ref else { continue }
            let key = "\(r)"; guard seen.insert(key).inserted else { continue }
            out.append(CatalogResult(id: key, title: decodeEntities(title),
                                     subtitle: prefix, ref: r))
            if out.count >= 80 { break }
        }
        return out
    }

    private static func firstGroup(_ s: String, _ pat: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
    private static func firstMatch(_ s: String, _ pat: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) else { return nil }
        return String(s[r])
    }
    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&#39;", with: "'")
    }

    // MARK: Internet Archive (broadened: sort by downloads, 80 rows)

    private static func ia(_ query: String, collections: [String]?) async throws -> [CatalogResult] {
        let q0 = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var q = q0.isEmpty ? "*:*" : q0
        if let cs = collections, !cs.isEmpty {
            let clause = cs.map { "collection:\($0)" }.joined(separator: " OR ")
            q = "(\(clause))" + (q0.isEmpty ? "" : " AND (\(q0))")
        } else if q0.isEmpty {
            return []   // don't dump all of IA on an empty plain query
        }
        var c = URLComponents(string: "https://archive.org/advancedsearch.php")!
        c.queryItems = [
            .init(name: "q", value: q),
            .init(name: "fl[]", value: "identifier"),
            .init(name: "fl[]", value: "title"),
            .init(name: "fl[]", value: "mediatype"),
            .init(name: "fl[]", value: "year"),
            .init(name: "sort[]", value: "downloads desc"),
            .init(name: "rows", value: "80"),
            .init(name: "page", value: "1"),
            .init(name: "output", value: "json"),
        ]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 15
        req.setValue("Fetch/0.1 (legal torrent client)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let resp = root["response"] as? [String: Any],
            let docs = resp["docs"] as? [[String: Any]]
        else { return [] }
        return docs.compactMap { d in
            guard let id = d["identifier"] as? String else { return nil }
            let mt = d["mediatype"] as? String ?? "data"
            let yr = str(d["year"]).map { " · \($0)" } ?? ""
            let url = URL(string: "https://archive.org/download/\(id)/\(id)_archive.torrent")!
            return CatalogResult(id: id, title: str(d["title"]) ?? id,
                                 subtitle: "\(mt)\(yr) · \(id)", ref: .torrentURL(url))
        }
    }

    // MARK: Academic Torrents (best-effort parse of the public browse page)

    private static func academic(_ query: String) async throws -> [CatalogResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var c = URLComponents(string: "https://academictorrents.com/browse.php")!
        c.queryItems = [.init(name: "search", value: q)]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 15
        req.setValue("Fetch/0.1", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        let html = String(decoding: data, as: UTF8.self)
        // Rows look like: <a href="/details/<hash>">Title</a> … magnet:?xt=urn:btih:<hash>
        let re = try NSRegularExpression(
            pattern: #"/details/([0-9a-fA-F]{40})"[^>]*>([^<]{2,160})</a>"#)
        var seen = Set<String>(); var out: [CatalogResult] = []
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let hR = Range(m.range(at: 1), in: html),
                  let tR = Range(m.range(at: 2), in: html) else { continue }
            let hash = String(html[hR]); guard seen.insert(hash).inserted else { continue }
            let title = String(html[tR])
                .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespaces)
            let magnet = "magnet:?xt=urn:btih:\(hash)&dn=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce"
            out.append(CatalogResult(id: hash, title: title,
                                     subtitle: "Academic Torrents · dataset",
                                     ref: .magnet(magnet)))
            if out.count >= 60 { break }
        }
        return out
    }

    // MARK: Curated official distro torrents (pinned snapshots; legal by source)

    private static let distros: [CatalogResult] = [
        d("Arch Linux (latest, rolling)", "https://archlinux.org/iso/latest/archlinux-x86_64.iso.torrent"),
        d("Debian 12 netinst (amd64)", "https://cdimage.debian.org/debian-cd/current/amd64/bt-cd/debian-12.8.0-amd64-netinst.iso.torrent"),
        d("Ubuntu 24.04 Desktop (amd64)", "https://releases.ubuntu.com/24.04/ubuntu-24.04.1-desktop-amd64.iso.torrent"),
        d("Ubuntu 24.04 Server (amd64)", "https://releases.ubuntu.com/24.04/ubuntu-24.04.1-live-server-amd64.iso.torrent"),
        d("Linux Mint 21.3 Cinnamon", "https://torrents.linuxmint.com/torrents/linuxmint-21.3-cinnamon-64bit.iso.torrent"),
        d("Fedora Workstation 40 (x86_64)", "https://torrent.fedoraproject.org/torrents/Fedora-Workstation-Live-x86_64-40.torrent"),
    ]
    private static func d(_ name: String, _ url: String) -> CatalogResult {
        CatalogResult(id: url, title: name, subtitle: "Official ISO · free-licensed",
                      ref: .torrentURL(URL(string: url)!))
    }

    // MARK: helpers

    private static func filter(_ items: [CatalogResult], _ q: String) -> [CatalogResult] {
        let t = q.trimmingCharacters(in: .whitespaces).lowercased()
        return t.isEmpty ? items : items.filter { $0.title.lowercased().contains(t) }
    }
    private static func str(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let a = v as? [String] { return a.first }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }
}
