import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Fetch palette — green accent for interactive bits, dark teal panels
// (same house-style structure as Espresso/Port/Alfred).
private let accent = Color(red: 0.18, green: 0.80, blue: 0.62)        // #2ECC9E
private let accentDark = Color(red: 0.063, green: 0.176, blue: 0.137) // #102D23

struct ContentView: View {
    @Environment(FetchStore.self) private var store
    @State private var pasteFocused = false

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: 46)
            Divider()
            ScrollView {
                VStack(spacing: 14) {
                    addCard
                    torrentsCard
                }
                .padding(14)
            }
            Divider()
            footer.frame(height: 46)
        }
        .frame(width: 380, height: 520)
        .glassScrollers()
        .tint(accent)
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        let active = store.downloads.contains { $0.state == .downloading }
        return HStack(spacing: 8) {
            Image(systemName: active ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.system(size: 16))
                .foregroundStyle(active ? accent : .secondary)
            Text("FETCH").font(.system(size: 13, weight: .semibold)).tracking(3)
            Spacer()
            Text(store.torrents.isEmpty
                 ? "Idle"
                 : "\(store.downloads.count) ↓   \(store.seeding.count) ⇡")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(active ? accent : .secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: Add card — one paste field, one Add button

    private var addCard: some View {
        @Bindable var s = store
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NoRingTextField(
                    text: $s.pasteInput,
                    isFocused: $pasteFocused,
                    placeholder: "Paste a magnet link, .torrent URL, or path…",
                    onSubmit: { store.add() }
                )
                .frame(height: 14)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(pasteFocused ? accent : Color.white.opacity(0.12),
                                lineWidth: 1)
                )
                .animation(.easeOut(duration: 0.12), value: pasteFocused)
                Button("Add") { store.add() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.pasteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button { if let u = pickTorrent() { store.importTorrent(at: u) } } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .controlSize(.small).help("Import a .torrent file")
            }
        }
        .padding(14).frame(maxWidth: .infinity).background(card)
    }

    // MARK: Torrents card — single unified list with progress

    private var torrentsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TORRENTS").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
            if store.torrents.isEmpty {
                Text("Nothing yet. Paste a magnet link or torrent above.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            } else {
                ForEach(Array(store.torrents.enumerated()), id: \.element.id) { i, t in
                    row(t)
                    if i < store.torrents.count - 1 { Divider().padding(.horizontal, 12) }
                }
            }
        }
        .padding(.bottom, 6).frame(maxWidth: .infinity).background(card)
    }

    @ViewBuilder
    private func row(_ t: TorrentStatus) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(t.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                Text(t.state.label).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            ProgressView(value: t.progress).tint(accent)
            HStack(spacing: 10) {
                Text("\(Int(t.progress * 100))%")
                if t.isActiveDownload {
                    Text("↓\(FetchStore.speed(t.downloadSpeed))")
                    Text("\(t.peers)p")
                } else if t.isSeeding {
                    Text("↑\(FetchStore.speed(t.uploadSpeed))")
                    Text("shared \(FetchStore.bytes(t.uploadedBytes))")
                }
                Spacer()
                Button("Open") { openTorrent(t) }
                    .controlSize(.mini)
                    .disabled(t.progress <= 0)
                Button(t.state == .paused ? "Resume" : "Pause") {
                    t.state == .paused ? store.resume(t) : store.pause(t)
                }.controlSize(.mini)
                Button(role: .destructive) {
                    store.remove(t, deleteData: false)
                } label: { Image(systemName: "xmark") }.controlSize(.mini)
            }
            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 5) {
            if let err = store.lastError {
                Text(err).font(.system(size: 10)).foregroundStyle(.red)
                    .lineLimit(2).onTapGesture { store.lastError = nil }
            }
            HStack(spacing: 10) {
                Button { if let u = pickFolder() { store.setDownloadDirectory(u) } } label: {
                    Image(systemName: "folder")
                }.controlSize(.small).help(store.downloadDirectory.path)
                Text(store.downloadDirectory.lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                }.controlSize(.small).help("Quit Fetch")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(accentDark.opacity(0.34))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(accent.opacity(0.20), lineWidth: 1))
    }

    // MARK: Panels

    private func pickTorrent() -> URL? {
        let p = NSOpenPanel()
        p.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        p.allowsMultipleSelection = false
        return p.runModal() == .OK ? p.url : nil
    }
    private func pickFolder() -> URL? {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.directoryURL = store.downloadDirectory
        return p.runModal() == .OK ? p.url : nil
    }

    // MARK: Open downloaded file

    /// Opens the torrent's payload in the default app.
    /// - If it's a single file (e.g. a .mp4), QuickTime (or whatever's set as
    ///   default for that type) takes it.
    /// - If it's a folder (multi-file torrent), Finder opens the folder.
    /// - If neither path exists yet, we fall back to revealing the partial
    ///   file or the download directory so the user still gets *something*.
    private func openTorrent(_ t: TorrentStatus) {
        let fm = FileManager.default
        let target = store.downloadDirectory.appendingPathComponent(t.name)
        if fm.fileExists(atPath: target.path) {
            NSWorkspace.shared.open(target)
            return
        }
        // libtorrent sometimes leaves a `.part` suffix on partials.
        let part = store.downloadDirectory.appendingPathComponent(t.name + ".part")
        if fm.fileExists(atPath: part.path) {
            NSWorkspace.shared.activateFileViewerSelecting([part])
            return
        }
        NSWorkspace.shared.open(store.downloadDirectory)
    }
}

// MARK: - NoRingTextField
//
// SwiftUI's TextField on macOS draws the system blue focus ring around the
// underlying NSTextField. There's no public SwiftUI API to turn it off, so we
// drop down to a tiny NSViewRepresentable wrapper that sets
// `focusRingType = .none`, exposes the focus state via a binding, and lets the
// SwiftUI side draw whatever ring/shadow it wants on top.
struct NoRingTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.focusRingType = .none
        tf.isBordered = false
        tf.drawsBackground = false
        tf.font = .systemFont(ofSize: 12)
        tf.placeholderString = placeholder
        tf.delegate = context.coordinator
        tf.cell?.usesSingleLineMode = true
        tf.cell?.wraps = false
        tf.cell?.isScrollable = true
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        nsView.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NoRingTextField
        init(_ p: NoRingTextField) { parent = p }

        func controlTextDidChange(_ note: Notification) {
            if let tf = note.object as? NSTextField {
                parent.text = tf.stringValue
            }
        }
        func controlTextDidBeginEditing(_ note: Notification) {
            DispatchQueue.main.async { self.parent.isFocused = true }
        }
        func controlTextDidEndEditing(_ note: Notification) {
            DispatchQueue.main.async { self.parent.isFocused = false }
        }
        func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}
