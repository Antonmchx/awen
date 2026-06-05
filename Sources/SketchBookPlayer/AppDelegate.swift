import AppKit
import SwiftUI
import Combine

@main
struct SketchBookPlayerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var playerWindowController: PlayerWindowController?
    private var controlWindowController: NSWindowController?
    private var favoritesWindowController: NSWindowController?
    private var playlistsWindowController: NSWindowController?
    private var isControlPanelCollapsed = false
    private var controlHostingView: NSHostingView<ControllerView>?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        appState.loadBundledSampleIfNeeded()

        let playerWindowController = PlayerWindowController(appState: appState)
        playerWindowController.showWindow(nil)
        self.playerWindowController = playerWindowController

        let controllerRootView = makeControllerRootView()
        let hostingView = NSHostingView(rootView: controllerRootView)
        controlHostingView = hostingView

        let controlWindow = NSWindow(
            contentRect: NSRect(x: 220, y: 260, width: 420, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        controlWindow.title = "awen"
        controlWindow.titleVisibility = .hidden
        controlWindow.titlebarAppearsTransparent = true
        controlWindow.isMovableByWindowBackground = true
        controlWindow.isOpaque = false
        controlWindow.backgroundColor = .clear
        controlWindow.alphaValue = appState.panelBackgroundMode == .glass ? 1.0 : CGFloat(appState.controlPanelOpacity)
        controlWindow.contentView = hostingView

        let controlWindowController = NSWindowController(window: controlWindow)
        controlWindowController.showWindow(nil)
        self.controlWindowController = controlWindowController
        updateControlPanelWindowHeight(animated: false)

        Publishers.CombineLatest(appState.$controlPanelOpacity, appState.$panelBackgroundMode)
            .sink { [weak self] opacity, mode in
                self?.applyPanelWindowAppearance(opacity: opacity, mode: mode)
            }
            .store(in: &cancellables)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.shutdown()
    }

    private func setPin(_ pinned: Bool) {
        appState.isPinnedToTop = pinned
        playerWindowController?.setPinned(pinned)
    }

    private func toggleControlPanelCollapse() {
        isControlPanelCollapsed.toggle()
        controlHostingView?.rootView = makeControllerRootView()
        updateControlPanelWindowHeight(animated: true)
    }

    private func makeControllerRootView() -> ControllerView {
        ControllerView(
            appState: appState,
            isCollapsed: isControlPanelCollapsed,
            onSetPin: { [weak self] isPinned in self?.setPin(isPinned) },
            onReload: { [weak self] in self?.playerWindowController?.reloadArtwork() },
            onToggleFullscreen: { [weak self] in self?.playerWindowController?.toggleFullscreen() },
            onTakeScreenshot: { [weak self] in self?.playerWindowController?.saveScreenshot() },
            onOpenFavorites: { [weak self] in self?.showFavoritesWindow() },
            onOpenPlaylists: { [weak self] in self?.showPlaylistsWindow() },
            onToggleCollapse: { [weak self] in self?.toggleControlPanelCollapse() }
        )
    }

    private func updateControlPanelWindowHeight(animated: Bool) {
        guard let window = controlWindowController?.window,
              let hostingView = controlHostingView else { return }

        hostingView.layoutSubtreeIfNeeded()
        let targetContentHeight: CGFloat = isControlPanelCollapsed
            ? 52
            : max(250, ceil(hostingView.fittingSize.height))

        let targetFrame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 420, height: targetContentHeight))
        var frame = window.frame
        frame.origin.y += frame.size.height - targetFrame.size.height
        frame.size.height = targetFrame.size.height
        frame.size.width = targetFrame.size.width
        window.setFrame(frame, display: true, animate: animated)
    }

    private func applyPanelWindowAppearance(opacity: Double, mode: PanelBackgroundMode) {
        let alpha: CGFloat = mode == .glass ? 1.0 : CGFloat(opacity)
        controlWindowController?.window?.alphaValue = alpha
        favoritesWindowController?.window?.alphaValue = alpha
        playlistsWindowController?.window?.alphaValue = alpha
    }

    private func showFavoritesWindow() {
        if let favoritesWindowController {
            favoritesWindowController.showWindow(nil)
            favoritesWindowController.window?.makeKeyAndOrderFront(nil)
            return
        }

        let favoritesWindow = NSWindow(
            contentRect: NSRect(x: 680, y: 300, width: 380, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        favoritesWindow.title = "Favorites"
        favoritesWindow.titleVisibility = .hidden
        favoritesWindow.titlebarAppearsTransparent = true
        favoritesWindow.isMovableByWindowBackground = true
        favoritesWindow.isOpaque = false
        favoritesWindow.backgroundColor = .clear
        favoritesWindow.alphaValue = appState.panelBackgroundMode == .glass ? 1.0 : CGFloat(appState.controlPanelOpacity)
        favoritesWindow.contentView = NSHostingView(rootView: FavoritesWindowView(appState: appState))

        let controller = NSWindowController(window: favoritesWindow)
        controller.showWindow(nil)
        favoritesWindowController = controller
    }

    private func showPlaylistsWindow() {
        if let playlistsWindowController {
            playlistsWindowController.showWindow(nil)
            playlistsWindowController.window?.makeKeyAndOrderFront(nil)
            return
        }

        let playlistsWindow = NSWindow(
            contentRect: NSRect(x: 720, y: 260, width: 440, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        playlistsWindow.title = "Playlists"
        playlistsWindow.titleVisibility = .hidden
        playlistsWindow.titlebarAppearsTransparent = true
        playlistsWindow.isMovableByWindowBackground = true
        playlistsWindow.isOpaque = false
        playlistsWindow.backgroundColor = .clear
        playlistsWindow.alphaValue = appState.panelBackgroundMode == .glass ? 1.0 : CGFloat(appState.controlPanelOpacity)
        playlistsWindow.contentView = NSHostingView(rootView: PlaylistsWindowView(appState: appState))

        let controller = NSWindowController(window: playlistsWindow)
        controller.showWindow(nil)
        playlistsWindowController = controller
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit awen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        return mainMenu
    }
}
