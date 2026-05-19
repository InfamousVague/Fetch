import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let accent = Color(red: 0.18, green: 0.80, blue: 0.62) // #2ECC9E

enum FetchTab: String, CaseIterable, Identifiable {
    case search = "Search", downloads = "Downloads", seeding = "Seeding"
    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(FetchStore.self) private var store
    @State private var tab: FetchTab = .search
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            addBar
            Divider()
            Picker("", selection: $tab) {
                ForEach(FetchTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            content
            if let err = store.lastError {
                Divider()
                Text(err).font(.system(size: 11)).foregroundStyle(.red)
                    .padding(8).onTapGesture { store.lastError = nil }
            }
        }
        .frame(width: 440, height: 580)
        .tint(accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(store).tint(accent).preferredColorScheme(.dark)
        }
    }

    // MARK: Header / add bar

    private var header: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(accent)
            Text("FETCH").font(.system(size: 14, weight: .semibold)).tracking(3)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help("Sources")
            Button {
                if let url = pickFolder() { store.setDownloadDirectory(url) }
            } label: {
                Label(store.downloadDirectory.lastPathComponent, systemImage: "folder")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help(store.downloadDirectory.path)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            @Bindable var s = store
            TextField("Paste a magnet link…", text: $s.magnetInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.addMagnet() }
            Button("Add") { store.addMagnet() }
                .disabled(store.magnetInput.isEmpty)
            Button {
                if let url = pickTorrent() { store.importTorrent(at: url) }
            } label: { Label("Import .torrent", systemImage: "doc.badge.plus") }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .search: searchView
        case .downloads: downloadsView
        case .seeding: seedingView
        }
    }

    private var searchView: some View {
        VStack(spacing: 0) {
            @Bindable var s = store
            Picker("Source", selection: $s.selectedSourceID) {
                ForEach(store.sources) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 16).padding(.top, 12)
            HStack(spacing: 8) {
                TextField("Search legal sources…", text: $s.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.search() }
                Button("Search") { store.search() }
                if store.searching { ProgressView().controlSize(.small) }
            }
            .padding(16)
            if store.searchResults.isEmpty {
                Text("Pick a source and search. Built-ins are legal by source; custom Torznab/RSS sources are yours to manage in Sources (⋯).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.searchResults) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(item.subtitle)
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Download") { store.download(item) }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var downloadsView: some View {
        listOrEmpty(store.downloads, empty: "No active downloads. Add a magnet, import a .torrent, or search.") { t in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(t.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text(t.state.label).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                ProgressView(value: t.progress).tint(accent)
                HStack(spacing: 14) {
                    Text("\(Int(t.progress * 100))%")
                    Text("↓ \(FetchStore.speed(t.downloadSpeed))")
                    Text("↑ \(FetchStore.speed(t.uploadSpeed))")
                    Text("\(t.peers) peers")
                    Text(FetchStore.bytes(t.downloadedBytes) + " / " + FetchStore.bytes(t.totalBytes))
                    Spacer()
                    Button(t.state == .paused ? "Resume" : "Pause") {
                        t.state == .paused ? store.resume(t) : store.pause(t)
                    }
                    Button("Remove", role: .destructive) { store.remove(t, deleteData: false) }
                }
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var seedingView: some View {
        listOrEmpty(store.seeding, empty: "Nothing seeding yet. Completed downloads keep seeding here.") { t in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("↑ \(FetchStore.speed(t.uploadSpeed))  ·  shared \(FetchStore.bytes(t.uploadedBytes))  ·  \(t.seeds) seeds")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Remove", role: .destructive) { store.remove(t, deleteData: false) }
            }
            .padding(.vertical, 4)
        }
    }

    private func listOrEmpty<T: Identifiable, Row: View>(
        _ items: [T], empty: String, @ViewBuilder row: @escaping (T) -> Row
    ) -> some View {
        Group {
            if items.isEmpty {
                Text(empty).font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { row($0) }.listStyle(.inset)
            }
        }
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
}

// MARK: - Sources settings

private struct SettingsView: View {
    @Environment(FetchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var trackerURL = ""
    @State private var tzName = ""
    @State private var tzURL = ""
    @State private var tzKey = ""
    @State private var feedName = ""
    @State private var feedURL = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SOURCES").font(.system(size: 13, weight: .semibold)).tracking(2)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Built-in legal providers") {
                        ForEach(CatalogProvider.allCases) { p in
                            Toggle(p.rawValue, isOn: Binding(
                                get: { !store.settings.disabledBuiltins.contains(p.rawValue) },
                                set: { store.setBuiltin(p, enabled: $0) }))
                                .toggleStyle(.switch).controlSize(.small)
                        }
                    }
                    section("Custom indexers (Torznab / Newznab)") {
                        Text("Standard indexer API — you supply the endpoint & key. Fetch ships none.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        ForEach(store.settings.torznab) { t in
                            row(t.name.isEmpty ? t.url : t.name) { store.removeTorznab(t.id) }
                        }
                        TextField("Name", text: $tzName).textFieldStyle(.roundedBorder)
                        TextField("Torznab URL (…/api?t=search)", text: $tzURL).textFieldStyle(.roundedBorder)
                        TextField("API key", text: $tzKey).textFieldStyle(.roundedBorder)
                        Button("Add indexer") {
                            store.addTorznab(name: tzName, url: tzURL, apiKey: tzKey)
                            tzName = ""; tzURL = ""; tzKey = ""
                        }.disabled(tzURL.isEmpty)
                    }
                    section("Custom RSS / Atom feeds") {
                        ForEach(store.settings.feeds) { f in
                            row(f.name.isEmpty ? f.url : f.name) { store.removeFeed(f.id) }
                        }
                        TextField("Name", text: $feedName).textFieldStyle(.roundedBorder)
                        TextField("Feed URL", text: $feedURL).textFieldStyle(.roundedBorder)
                        Button("Add feed") {
                            store.addFeed(name: feedName, url: feedURL)
                            feedName = ""; feedURL = ""
                        }.disabled(feedURL.isEmpty)
                    }
                    section("Extra trackers (appended to added magnets)") {
                        ForEach(store.settings.trackers, id: \.self) { tr in
                            row(tr) { store.removeTracker(tr) }
                        }
                        HStack {
                            TextField("udp://tracker…/announce", text: $trackerURL)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") { store.addTracker(trackerURL); trackerURL = "" }
                                .disabled(trackerURL.isEmpty)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 560)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }
    private func row(_ text: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(text).font(.system(size: 11)).lineLimit(1)
            Spacer()
            Button(role: .destructive) { remove() } label: {
                Image(systemName: "minus.circle")
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }
}
