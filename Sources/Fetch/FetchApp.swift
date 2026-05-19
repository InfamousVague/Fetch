import SwiftUI
import AppKit

@main
struct FetchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Accessory app: the real UI is the NSStatusItem/NSPopover the
        // delegate manages (suite pattern — like Espresso/Alfred/Port).
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: FetchStore = {
        let dir = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fetch", isDirectory: true)
        let engine: TorrentEngine = LibtorrentEngine(saveDirectory: dir) ?? StubEngine()
        return FetchStore(engine: engine)
    }()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        updateIcon()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environment(store)
        )

        store.onStatus = { [weak self] in self?.updateIcon() }
        store.start()                       // poll/download even if popover never opened
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let active = !store.downloads.filter { $0.state == .downloading }.isEmpty
        let img = NSImage(systemSymbolName: active ? "arrow.down.circle.fill" : "arrow.down.circle",
                          accessibilityDescription: "Fetch")
        img?.isTemplate = true
        button.image = img
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
