import Foundation
import CFetchEngine

/// Real BitTorrent engine: thin Swift wrapper over the C shim → libtorrent 2.0.
final class LibtorrentEngine: TorrentEngine {
    private let handle: OpaquePointer
    private(set) var downloadDirectory: URL

    init?(saveDirectory: URL) {
        try? FileManager.default.createDirectory(
            at: saveDirectory, withIntermediateDirectories: true)
        guard let h = saveDirectory.path.withCString({ fe_create($0) }) else {
            return nil
        }
        handle = OpaquePointer(h)
        downloadDirectory = saveDirectory
    }

    deinit { fe_destroy(UnsafeMutableRawPointer(handle)) }

    func setDownloadDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        url.path.withCString { fe_set_save_path(UnsafeMutableRawPointer(handle), $0) }
        downloadDirectory = url
    }

    @discardableResult
    func addMagnet(_ uri: String) throws -> String {
        let rc = uri.withCString { fe_add_magnet(UnsafeMutableRawPointer(handle), $0) }
        if rc != 0 { throw EngineError.invalidMagnet }
        return uri
    }

    @discardableResult
    func addTorrent(data: Data, fallbackName: String) throws -> String {
        let rc = data.withUnsafeBytes { raw -> Int32 in
            fe_add_buffer(UnsafeMutableRawPointer(handle),
                          raw.bindMemory(to: UInt8.self).baseAddress,
                          CLong(data.count))
        }
        if rc != 0 { throw EngineError.invalidTorrentData }
        return fallbackName
    }

    func pause(_ id: String) {
        id.withCString { fe_pause(UnsafeMutableRawPointer(handle), $0) }
    }
    func resume(_ id: String) {
        id.withCString { fe_resume(UnsafeMutableRawPointer(handle), $0) }
    }
    func remove(_ id: String, deleteData: Bool) {
        id.withCString { fe_remove(UnsafeMutableRawPointer(handle), $0, deleteData ? 1 : 0) }
    }

    func poll() -> [TorrentStatus] {
        var buf = [FEStatus](repeating: FEStatus(), count: 256)
        let count = buf.withUnsafeMutableBufferPointer { p in
            Int(fe_poll(UnsafeMutableRawPointer(handle), p.baseAddress, Int32(p.count)))
        }
        return (0..<max(0, count)).map { Self.map(buf[$0]) }
    }

    private static func map(_ s: FEStatus) -> TorrentStatus {
        TorrentStatus(
            id: cstr(s.id),
            name: cstr(s.name),
            progress: s.progress,
            downloadSpeed: Int(s.down_rate),
            uploadSpeed: Int(s.up_rate),
            peers: Int(s.peers),
            seeds: Int(s.seeds),
            totalBytes: s.total_bytes,
            downloadedBytes: s.done_bytes,
            uploadedBytes: s.uploaded_bytes,
            state: state(s.state),
            savePath: ""
        )
    }

    private static func state(_ i: Int32) -> TorrentState {
        switch i {
        case 1: return .checking
        case 2: return .downloading
        case 3: return .seeding
        case 4: return .paused
        case 5: return .error
        default: return .queued
        }
    }

    /// Read a fixed C char array (imported as a tuple) into a Swift String.
    private static func cstr<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }
}
