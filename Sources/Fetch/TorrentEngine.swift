import Foundation

enum TorrentState: String {
    case queued, checking, downloading, seeding, paused, done, error

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .checking: return "Checking"
        case .downloading: return "Downloading"
        case .seeding: return "Seeding"
        case .paused: return "Paused"
        case .done: return "Done"
        case .error: return "Error"
        }
    }
}

struct TorrentStatus: Identifiable, Hashable {
    let id: String
    var name: String
    var progress: Double          // 0...1
    var downloadSpeed: Int        // bytes/sec
    var uploadSpeed: Int          // bytes/sec
    var peers: Int
    var seeds: Int
    var totalBytes: Int64
    var downloadedBytes: Int64
    var uploadedBytes: Int64
    var state: TorrentState
    var savePath: String

    var isActiveDownload: Bool { state == .downloading || state == .queued || state == .checking || state == .paused }
    var isSeeding: Bool { state == .seeding || state == .done }
}

/// The seam between the SwiftUI app and the BitTorrent engine. Phase 1
/// ships a `StubEngine`; Phase 2 adds a libtorrent-backed engine that
/// conforms to this same protocol — the UI never changes.
protocol TorrentEngine: AnyObject {
    var downloadDirectory: URL { get }
    func setDownloadDirectory(_ url: URL)

    @discardableResult func addMagnet(_ uri: String) throws -> String
    @discardableResult func addTorrent(data: Data, fallbackName: String) throws -> String

    func pause(_ id: String)
    func resume(_ id: String)
    func remove(_ id: String, deleteData: Bool)

    /// Snapshot of all torrents; the store polls this ~1s.
    func poll() -> [TorrentStatus]
}

enum EngineError: LocalizedError {
    case invalidMagnet
    case invalidTorrentData
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .invalidMagnet: return "That doesn't look like a valid magnet link."
        case .invalidTorrentData: return "That .torrent file couldn't be read."
        case .notImplemented(let what): return "\(what) isn't available yet (engine: stub)."
        }
    }
}
