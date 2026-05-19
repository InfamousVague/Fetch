import Foundation

/// Phase-1 placeholder: simulates realistic download/seed progress so the
/// whole UI is exercisable before the libtorrent engine lands. No network.
final class StubEngine: TorrentEngine {
    private struct Sim {
        var name: String
        var total: Int64
        var rate: Double          // simulated bytes/sec while downloading
        var downloaded: Double
        var uploaded: Double
        var paused = false
        var lastTick: Date
    }

    private var sims: [String: Sim] = [:]
    private(set) var downloadDirectory: URL =
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fetch", isDirectory: true)

    func setDownloadDirectory(_ url: URL) { downloadDirectory = url }

    @discardableResult
    func addMagnet(_ uri: String) throws -> String {
        guard uri.hasPrefix("magnet:?") else { throw EngineError.invalidMagnet }
        let name = Self.queryValue(uri, "dn") ?? "Magnet download"
        return add(name: name)
    }

    @discardableResult
    func addTorrent(data: Data, fallbackName: String) throws -> String {
        guard !data.isEmpty, data.first == UInt8(ascii: "d") else {
            throw EngineError.invalidTorrentData
        }
        return add(name: Self.bencodeName(data) ?? fallbackName)
    }

    func pause(_ id: String) { sims[id]?.paused = true }
    func resume(_ id: String) { sims[id]?.paused = false; sims[id]?.lastTick = Date() }
    func remove(_ id: String, deleteData: Bool) { sims[id] = nil }

    func poll() -> [TorrentStatus] {
        let now = Date()
        var out: [TorrentStatus] = []
        for (id, var s) in sims {
            let dt = now.timeIntervalSince(s.lastTick)
            s.lastTick = now
            var dl = 0, ul = 0
            if s.downloaded < Double(s.total) && !s.paused {
                s.downloaded = min(Double(s.total), s.downloaded + s.rate * dt)
                dl = Int(s.rate)
            }
            let complete = s.downloaded >= Double(s.total)
            if complete {                        // seed a while
                s.uploaded += 400_000 * dt
                ul = 400_000
            }
            sims[id] = s
            let state: TorrentState = s.paused ? .paused : (complete ? .seeding : .downloading)
            out.append(TorrentStatus(
                id: id, name: s.name,
                progress: Double(s.downloaded) / Double(s.total),
                downloadSpeed: dl, uploadSpeed: ul,
                peers: complete ? 3 : Int.random(in: 4...40),
                seeds: Int.random(in: 1...12),
                totalBytes: s.total,
                downloadedBytes: Int64(s.downloaded),
                uploadedBytes: Int64(s.uploaded),
                state: state,
                savePath: downloadDirectory.path
            ))
        }
        return out.sorted { $0.name < $1.name }
    }

    // MARK: helpers

    private func add(name: String) -> String {
        let id = UUID().uuidString
        let total = Int64.random(in: 250_000_000...4_500_000_000)
        sims[id] = Sim(name: name, total: total,
                       rate: Double(Int.random(in: 4_000_000...18_000_000)),
                       downloaded: 0, uploaded: 0, lastTick: Date())
        return id
    }

    private static func queryValue(_ uri: String, _ key: String) -> String? {
        URLComponents(string: uri)?.queryItems?
            .first(where: { $0.name == key })?.value?
            .removingPercentEncoding
    }

    /// Minimal bencode scan for the top-level `name` value (best-effort).
    private static func bencodeName(_ data: Data) -> String? {
        guard let s = String(data: data, encoding: .isoLatin1),
              let r = s.range(of: "4:name") else { return nil }
        let after = s[r.upperBound...]
        guard let colon = after.firstIndex(of: ":") else { return nil }
        let lenStr = after[after.startIndex..<colon]
        guard let len = Int(lenStr) else { return nil }
        let start = after.index(after: colon)
        guard let end = after.index(start, offsetBy: len, limitedBy: after.endIndex)
        else { return nil }
        return String(after[start..<end])
    }
}
