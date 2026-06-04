import AppKit
import SwiftUI
import WebKit
import Combine

@MainActor
final class PlayerWindowController: NSWindowController {
    private let appState: AppState
    private let webViewStore = WebViewStore()

    init(appState: AppState) {
        self.appState = appState

        let window = NSWindow(
            contentRect: NSRect(x: 620, y: 240, width: 900, height: 620),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 360, height: 240)

        let rootView = PlayerContainerView(appState: appState, webViewStore: webViewStore)
        window.contentView = NSHostingView(rootView: rootView)

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func reloadArtwork() {
        webViewStore.reload()
    }

    func setPinned(_ pinned: Bool) {
        window?.level = pinned ? .floating : .normal
    }

    func toggleFullscreen() {
        window?.toggleFullScreen(nil)
    }

    func saveScreenshot() {
        guard let webView = webViewStore.webView else {
            appState.statusMessage = "Artwork view is not ready yet."
            return
        }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = screenshotFileName()
        savePanel.title = "Save Artwork Screenshot"

        guard savePanel.runModal() == .OK, let destinationURL = savePanel.url else {
            appState.statusMessage = "Screenshot was cancelled."
            return
        }

        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true

        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.appState.statusMessage = "Screenshot failed: \(error.localizedDescription)"
                    return
                }

                guard let image,
                      let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    self.appState.statusMessage = "Screenshot conversion failed."
                    return
                }

                do {
                    try pngData.write(to: destinationURL)
                    self.appState.statusMessage = "Screenshot saved."
                } catch {
                    self.appState.statusMessage = "Could not save screenshot: \(error.localizedDescription)"
                }
            }
        }
    }

    private func screenshotFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "sketchbook-\(formatter.string(from: Date())).png"
    }
}

@MainActor
final class WebViewStore: ObservableObject {
    fileprivate weak var webView: WKWebView?

    func reload() {
        webView?.reload()
    }
}

struct PlayerContainerView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var webViewStore: WebViewStore

    var body: some View {
        Group {
            switch appState.playerFrameStyle {
            case .shell:
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)

                    ArtworkWebView(appState: appState, webViewStore: webViewStore)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(10)
                }
                .padding(8)

            case .thin:
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)

                    ArtworkWebView(appState: appState, webViewStore: webViewStore)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(3)
                }
                .padding(2)
            }
        }
        .background(Color.clear)
    }
}

struct ArtworkWebView: NSViewRepresentable {
    @ObservedObject var appState: AppState
    @ObservedObject var webViewStore: WebViewStore

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webViewStore.webView = webView
        loadCurrentSource(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.appState = appState
        loadCurrentSource(into: webView)
    }

    private func loadCurrentSource(into webView: WKWebView) {
        guard let source = appState.currentSource else { return }

        switch source {
        case .remote(let url):
            if webView.url != url {
                webView.load(URLRequest(url: url))
            }
        case .local(let fileURL, _):
            if webView.url != fileURL {
                let readAccessURL = fileURL.deletingLastPathComponent()
                webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var appState: AppState

        init(appState: AppState) {
            self.appState = appState
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            appState.updateCurrentPageTitle(webView.title)
        }
    }
}
