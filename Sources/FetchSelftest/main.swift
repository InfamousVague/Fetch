// Headless proof that the libtorrent engine actually works.
// Usage: FetchSelftest <path-to.torrent> [seconds]
import Foundation
import CFetchEngine

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: FetchSelftest <file.torrent> [seconds]\n".utf8))
    exit(2)
}
let torrentPath = args[1]
let seconds = args.count >= 3 ? (Int(args[2]) ?? 15) : 15

let saveDir = NSTemporaryDirectory() + "fetch-selftest"
try? FileManager.default.createDirectory(atPath: saveDir, withIntermediateDirectories: true)

guard let raw = saveDir.withCString({ fe_create($0) }) else {
    print("FAIL: fe_create returned null (libtorrent session init failed)")
    exit(1)
}
let eng = UnsafeMutableRawPointer(raw)

guard let data = FileManager.default.contents(atPath: torrentPath) else {
    print("FAIL: cannot read \(torrentPath)"); exit(1)
}
let rc = data.withUnsafeBytes { p in
    fe_add_buffer(eng, p.bindMemory(to: UInt8.self).baseAddress, CLong(data.count))
}
guard rc == 0 else { print("FAIL: fe_add_buffer rc=\(rc)"); exit(1) }
print("OK: torrent added to libtorrent session (\(data.count) bytes). Polling \(seconds)s…")

var buf = [FEStatus](repeating: FEStatus(), count: 16)
for t in 1...seconds {
    sleep(1)
    let n = buf.withUnsafeMutableBufferPointer { b in
        Int(fe_poll(eng, b.baseAddress, Int32(b.count)))
    }
    if n > 0 {
        let s = buf[0]
        let name = withUnsafeBytes(of: s.name) {
            String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let pct = String(format: "%.2f", s.progress * 100)
        print("[\(t)s] \(name) | \(pct)% | ↓\(s.down_rate)B/s | peers \(s.peers) seeds \(s.seeds) | state \(s.state) | done \(s.done_bytes)/\(s.total_bytes)")
    } else {
        print("[\(t)s] (no torrents in session)")
    }
}
fe_destroy(eng)
print("DONE")
