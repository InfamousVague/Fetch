import Foundation
import Observation

@MainActor
@Observable
final class FetchStore {
    var torrents: [TorrentStatus] = []
    var pasteInput = ""
    var lastError: String?
    var downloadDirectory: URL

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

    // MARK: Add

    /// One entry point that figures out whether the user pasted a magnet
    /// link, an http(s) URL to a .torrent, or a local file path. Keeps the
    /// UI to a single field + one button.
    func add() {
        let raw = pasteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        Task {
            do {
                if raw.hasPrefix("magnet:") {
                    try engine.addMagnet(raw)
                } else if let url = URL(string: raw),
                          let scheme = url.scheme?.lowercased(),
                          scheme == "http" || scheme == "https" {
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 30
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        throw EngineError.invalidTorrentData
                    }
                    let name = url.deletingPathExtension().lastPathComponent
                    try engine.addTorrent(data: data, fallbackName: name)
                } else {
                    // Treat as a local file path (with or without file://)
                    let path = raw.hasPrefix("file://")
                        ? URL(string: raw)?.path ?? raw
                        : raw
                    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    let data = try Data(contentsOf: url)
                    let name = url.deletingPathExtension().lastPathComponent
                    try engine.addTorrent(data: data, fallbackName: name)
                }
                self.pasteInput = ""
                self.poll()
            } catch {
                self.lastError = error.localizedDescription
            }
        }
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
