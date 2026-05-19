import Foundation
import Observation

@MainActor
@Observable
final class FetchStore {
    var torrents: [TorrentStatus] = []
    var searchQuery = ""
    var settings = SourceSettings.load()
    var selectedSourceID = "builtin:\(CatalogProvider.internetArchive.rawValue)"
    var searchResults: [CatalogResult] = []
    var searching = false
    var magnetInput = ""
    var lastError: String?
    var downloadDirectory: URL

    var sources: [SearchSource] { settings.searchSources }
    var selectedSource: SearchSource? {
        sources.first { $0.id == selectedSourceID } ?? sources.first
    }

    /// Called after each poll so the menu-bar icon can reflect state.
    @ObservationIgnored var onStatus: (() -> Void)?

    @ObservationIgnored private let engine: TorrentEngine
    @ObservationIgnored private var pollTimer: Timer?

    init(engine: TorrentEngine = StubEngine()) {
        self.engine = engine
        self.downloadDirectory = engine.downloadDirectory
        try? FileManager.default.createDirectory(
            at: engine.downloadDirectory, withIntermediateDirectories: true)
    }

    func start() {
        poll()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        torrents = engine.poll()
        onStatus?()
    }

    var downloads: [TorrentStatus] { torrents.filter(\.isActiveDownload) }
    var seeding: [TorrentStatus] { torrents.filter(\.isSeeding) }

    // MARK: Search

    func search() {
        guard let src = selectedSource else { return }
        let q = searchQuery
        searching = true
        searchResults = []
        Task {
            do {
                self.searchResults = try await Catalog.search(src, q)
            } catch {
                self.lastError = "Search failed: \(error.localizedDescription)"
            }
            self.searching = false
        }
    }

    func download(_ result: CatalogResult) {
        Task {
            do {
                switch result.ref {
                case .magnet(let m):
                    try engine.addMagnet(Catalog.withTrackers(m, settings.trackers))
                case .torrentURL(let url):
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 30
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        throw EngineError.invalidTorrentData
                    }
                    try engine.addTorrent(data: data, fallbackName: result.title)
                }
                poll()
            } catch {
                self.lastError = "Couldn't add \(result.title): \(error.localizedDescription)"
            }
        }
    }

    // MARK: Add / import

    func addMagnet() {
        let m = magnetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return }
        do {
            try engine.addMagnet(Catalog.withTrackers(m, settings.trackers))
            magnetInput = ""
            poll()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Sources settings (persisted)

    func setBuiltin(_ p: CatalogProvider, enabled: Bool) {
        if enabled { settings.disabledBuiltins.remove(p.rawValue) }
        else { settings.disabledBuiltins.insert(p.rawValue) }
        commitSettings()
    }
    func addTracker(_ url: String) {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !settings.trackers.contains(u) else { return }
        settings.trackers.append(u); commitSettings()
    }
    func removeTracker(_ url: String) { settings.trackers.removeAll { $0 == url }; commitSettings() }
    func addTorznab(name: String, url: String, apiKey: String) {
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        settings.torznab.append(TorznabIndexer(name: name, url: url, apiKey: apiKey))
        commitSettings()
    }
    func removeTorznab(_ id: String) { settings.torznab.removeAll { $0.id == id }; commitSettings() }
    func addFeed(name: String, url: String) {
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        settings.feeds.append(FeedSource(name: name, url: url)); commitSettings()
    }
    func removeFeed(_ id: String) { settings.feeds.removeAll { $0.id == id }; commitSettings() }

    private func commitSettings() {
        settings.save()
        if selectedSource == nil { selectedSourceID = sources.first?.id ?? "" }
    }

    func importTorrent(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            try engine.addTorrent(data: data, fallbackName: url.deletingPathExtension().lastPathComponent)
            poll()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Controls

    func pause(_ s: TorrentStatus) { engine.pause(s.id); poll() }
    func resume(_ s: TorrentStatus) { engine.resume(s.id); poll() }
    func remove(_ s: TorrentStatus, deleteData: Bool) { engine.remove(s.id, deleteData: deleteData); poll() }

    func setDownloadDirectory(_ url: URL) {
        engine.setDownloadDirectory(url)
        downloadDirectory = url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: Formatting

    static func bytes(_ n: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: n)
    }
    static func speed(_ n: Int) -> String {
        n <= 0 ? "—" : "\(bytes(Int64(n)))/s"
    }
}
