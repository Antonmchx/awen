import Foundation
import AppKit
import Combine

enum ArtworkSource: Equatable {
    case local(fileURL: URL, accessURL: URL?)
    case remote(URL)
}

enum PlayerFrameStyle: String, Codable, CaseIterable {
    case shell
    case thin
}

struct SavedArtworkLink: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var urlString: String
    let createdAt: Date

    init(id: UUID = UUID(), title: String, urlString: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
    }
}

struct SavedPlaylist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var intervalSeconds: Double
    var items: [SavedArtworkLink]

    init(id: UUID = UUID(), name: String, intervalSeconds: Double = 20, items: [SavedArtworkLink] = []) {
        self.id = id
        self.name = name
        self.intervalSeconds = intervalSeconds
        self.items = items
    }
}

private struct PersistedCurrentArtwork: Codable {
    var kind: String
    var location: String
}

private struct PersistedLibrary: Codable {
    var favorites: [SavedArtworkLink]
    var playlists: [SavedPlaylist]
    var selectedPlaylistID: UUID?
    var currentArtwork: PersistedCurrentArtwork?
    var playerFrameStyle: PlayerFrameStyle?
    var controlPanelOpacity: Double?
}

@MainActor
final class AppState: ObservableObject {
    @Published var currentSource: ArtworkSource?
    @Published var inputText: String = ""
    @Published var statusMessage: String = "Load a local `index.html` or enter a remote URL."
    @Published var isPinnedToTop: Bool = false
    @Published var favorites: [SavedArtworkLink] = []
    @Published var playlists: [SavedPlaylist] = []
    @Published var selectedPlaylistID: UUID?
    @Published var draftPlaylistName: String = ""
    @Published var isAutoplayEnabled: Bool = false
    @Published var playlistIntervalInput: String = "20"
    @Published var playerFrameStyle: PlayerFrameStyle = .shell
    @Published var currentPageTitle: String = ""
    @Published var controlPanelOpacity: Double = 0.96

    private let persistenceURL: URL
    private var securityScopedURL: URL?
    private var autoplayTimer: Timer?
    private var currentPlaylistIndex: Int = 0

    init() {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directoryURL = appSupportURL.appendingPathComponent("SketchBookPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        persistenceURL = directoryURL.appendingPathComponent("library.json")
        restoreLibrary()
    }

    var selectedPlaylist: SavedPlaylist? {
        guard let selectedPlaylistID else { return nil }
        return playlists.first(where: { $0.id == selectedPlaylistID })
    }

    var currentArtworkTitle: String {
        guard let currentSource else { return "No artwork loaded" }
        let renderedTitle = currentPageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !renderedTitle.isEmpty {
            return renderedTitle
        }

        switch currentSource {
        case .local(let fileURL, _):
            return fileURL.deletingPathExtension().lastPathComponent
        case .remote(let url):
            if let savedTitle = favorites.first(where: { $0.urlString == url.absoluteString })?.title {
                return savedTitle
            }

            for playlist in playlists {
                if let savedTitle = playlist.items.first(where: { $0.urlString == url.absoluteString })?.title {
                    return savedTitle
                }
            }

            return suggestedTitle(for: url)
        }
    }

    var selectedPlaylistInterval: Double {
        get { selectedPlaylist?.intervalSeconds ?? 20 }
        set { updateSelectedPlaylistInterval(newValue) }
    }

    @discardableResult
    func loadRemoteURL() -> Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = normalizedRemoteURL(from: trimmed) else {
            statusMessage = trimmed.isEmpty ? "Enter a URL first." : "Use an http or https URL."
            return false
        }

        loadRemoteURL(url, status: "Loaded remote artwork.")
        return true
    }

    func loadRemoteURL(_ url: URL, status: String) {
        stopAccessingSecurityScopeIfNeeded()
        currentPageTitle = ""
        inputText = url.absoluteString
        currentSource = .remote(url)
        statusMessage = status
        persistLibrary()
    }

    func addCurrentURLToFavorites() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = normalizedRemoteURL(from: trimmed) else {
            statusMessage = "Only remote http/https URLs can be saved to favorites."
            return
        }

        let normalized = url.absoluteString
        guard !favorites.contains(where: { $0.urlString == normalized }) else {
            statusMessage = "This URL is already in favorites."
            return
        }

        favorites.insert(
            SavedArtworkLink(title: suggestedTitle(for: url), urlString: normalized),
            at: 0
        )
        persistLibrary()
        statusMessage = "Saved to favorites."
    }

    func removeFavorite(_ favoriteID: UUID) {
        favorites.removeAll { $0.id == favoriteID }
        persistLibrary()
        statusMessage = "Removed favorite."
    }

    func updateFavorite(_ favoriteID: UUID, title: String, urlString: String) -> Bool {
        guard let normalizedURL = normalizedRemoteURL(from: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusMessage = "Use a valid http or https URL."
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            statusMessage = "Enter a title."
            return false
        }

        guard let index = favorites.firstIndex(where: { $0.id == favoriteID }) else {
            statusMessage = "Favorite was not found."
            return false
        }

        favorites[index].title = trimmedTitle
        favorites[index].urlString = normalizedURL.absoluteString
        persistLibrary()
        statusMessage = "Favorite updated."
        return true
    }

    func playFavorite(_ favorite: SavedArtworkLink) {
        guard let url = URL(string: favorite.urlString) else {
            statusMessage = "Favorite URL is invalid."
            return
        }

        loadRemoteURL(url, status: "Loaded favorite: \(favorite.title)")
    }

    func createPlaylist() {
        let trimmed = draftPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter a playlist name first."
            return
        }

        let playlist = SavedPlaylist(name: trimmed)
        playlists.append(playlist)
        selectedPlaylistID = playlist.id
        draftPlaylistName = ""
        syncPlaylistIntervalInput()
        persistLibrary()
        statusMessage = "Created playlist."
    }

    func importPlaylist(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let importedPlaylist = try JSONDecoder().decode(SavedPlaylist.self, from: data)
            let trimmedName = importedPlaylist.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseName = trimmedName.isEmpty ? "Imported Playlist" : trimmedName

            let playlist = SavedPlaylist(
                name: uniquePlaylistName(baseName),
                intervalSeconds: importedPlaylist.intervalSeconds,
                items: importedPlaylist.items
            )

            playlists.append(playlist)
            selectedPlaylistID = playlist.id
            syncPlaylistIntervalInput()
            persistLibrary()
            statusMessage = "Playlist imported."
        } catch {
            statusMessage = "Could not import playlist: \(error.localizedDescription)"
        }
    }

    func deletePlaylist(_ playlistID: UUID) {
        playlists.removeAll { $0.id == playlistID }
        if selectedPlaylistID == playlistID {
            selectedPlaylistID = playlists.first?.id
            syncPlaylistIntervalInput()
            stopAutoplay()
        }
        persistLibrary()
        statusMessage = "Deleted playlist."
    }

    func selectPlaylist(_ playlistID: UUID?) {
        selectedPlaylistID = playlistID
        currentPlaylistIndex = 0
        syncPlaylistIntervalInput()
        persistLibrary()
        if isAutoplayEnabled {
            restartAutoplayIfPossible()
        }
    }

    func addCurrentURLToSelectedPlaylist() {
        guard let selectedPlaylistID,
              let playlistIndex = playlists.firstIndex(where: { $0.id == selectedPlaylistID }) else {
            statusMessage = "Create or select a playlist first."
            return
        }

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = normalizedRemoteURL(from: trimmed) else {
            statusMessage = "Only remote http/https URLs can be added to playlists."
            return
        }

        let normalized = url.absoluteString
        if playlists[playlistIndex].items.contains(where: { $0.urlString == normalized }) {
            statusMessage = "This URL is already in the selected playlist."
            return
        }

        playlists[playlistIndex].items.append(
            SavedArtworkLink(title: suggestedTitle(for: url), urlString: normalized)
        )
        persistLibrary()
        statusMessage = "Added to playlist."
        if isAutoplayEnabled {
            restartAutoplayIfPossible()
        }
    }

    func removeItemFromSelectedPlaylist(_ itemID: UUID) {
        guard let selectedPlaylistID,
              let playlistIndex = playlists.firstIndex(where: { $0.id == selectedPlaylistID }) else {
            return
        }

        playlists[playlistIndex].items.removeAll { $0.id == itemID }
        currentPlaylistIndex = 0
        persistLibrary()
        statusMessage = "Removed item from playlist."
        if isAutoplayEnabled {
            restartAutoplayIfPossible()
        }
    }

    func updateItemInSelectedPlaylist(_ itemID: UUID, title: String, urlString: String) -> Bool {
        guard let selectedPlaylistID,
              let playlistIndex = playlists.firstIndex(where: { $0.id == selectedPlaylistID }) else {
            statusMessage = "Select a playlist first."
            return false
        }

        guard let normalizedURL = normalizedRemoteURL(from: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusMessage = "Use a valid http or https URL."
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            statusMessage = "Enter a title."
            return false
        }

        guard let itemIndex = playlists[playlistIndex].items.firstIndex(where: { $0.id == itemID }) else {
            statusMessage = "Playlist item was not found."
            return false
        }

        playlists[playlistIndex].items[itemIndex].title = trimmedTitle
        playlists[playlistIndex].items[itemIndex].urlString = normalizedURL.absoluteString
        persistLibrary()
        statusMessage = "Playlist item updated."
        return true
    }

    func playSelectedPlaylistNow() {
        guard let playlist = selectedPlaylist else {
            statusMessage = "Select a playlist first."
            return
        }
        guard !playlist.items.isEmpty else {
            statusMessage = "The selected playlist is empty."
            return
        }

        currentPlaylistIndex = 0
        playPlaylistItem(at: currentPlaylistIndex, in: playlist)
        if isAutoplayEnabled {
            restartAutoplayIfPossible()
        }
    }

    func playNextPlaylistItem() {
        guard let playlist = selectedPlaylist else {
            statusMessage = "Select a playlist first."
            return
        }
        guard !playlist.items.isEmpty else {
            statusMessage = "The selected playlist is empty."
            return
        }

        currentPlaylistIndex = (currentPlaylistIndex + 1) % playlist.items.count
        playPlaylistItem(at: currentPlaylistIndex, in: playlist)
    }

    func setAutoplayEnabled(_ enabled: Bool) {
        isAutoplayEnabled = enabled
        enabled ? restartAutoplayIfPossible() : stopAutoplay()
    }

    func updateSelectedPlaylistInterval(_ seconds: Double) {
        guard let selectedPlaylistID,
              let playlistIndex = playlists.firstIndex(where: { $0.id == selectedPlaylistID }) else {
            return
        }

        playlists[playlistIndex].intervalSeconds = min(max(seconds, 3), 600)
        syncPlaylistIntervalInput()
        persistLibrary()
        if isAutoplayEnabled {
            restartAutoplayIfPossible()
        }
    }

    func applySelectedPlaylistIntervalInput() {
        let trimmed = playlistIntervalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Double(trimmed), seconds.isFinite else {
            statusMessage = "Enter a valid number of seconds."
            syncPlaylistIntervalInput()
            return
        }

        updateSelectedPlaylistInterval(seconds)
        statusMessage = "Autoplay interval set."
    }

    func setPlayerFrameStyle(_ style: PlayerFrameStyle) {
        playerFrameStyle = style
        persistLibrary()
    }

    func setControlPanelOpacity(_ opacity: Double) {
        controlPanelOpacity = min(max(opacity, 0.35), 1.0)
        persistLibrary()
    }

    func loadLocalFile(_ url: URL) {
        stopAccessingSecurityScopeIfNeeded()

        let accessGranted = url.startAccessingSecurityScopedResource()
        if accessGranted {
            securityScopedURL = url
        }

        currentPageTitle = ""
        currentSource = .local(fileURL: url, accessURL: accessGranted ? url : nil)
        inputText = url.path
        statusMessage = "Loaded local artwork."
        persistLibrary()
    }

    func loadBundledSampleIfNeeded() {
        guard currentSource == nil else { return }
        guard let sampleURL = bundledSampleURL() else {
            statusMessage = "Sample artwork was not found."
            return
        }

        currentPageTitle = ""
        currentSource = .local(fileURL: sampleURL, accessURL: nil)
        inputText = sampleURL.path
        statusMessage = "Loaded bundled sample artwork."
        persistLibrary()
    }

    private func bundledSampleURL() -> URL? {
        let relativeCandidates = [
            "SketchBookPlayer_SketchBookPlayer.bundle/index.html",
            "SketchBookPlayer_SketchBookPlayer.bundle/SampleWork/index.html",
            "SampleWork/index.html",
            "index.html"
        ]

        let baseDirectories = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true),
            Bundle.main.executableURL?.deletingLastPathComponent(),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("SampleWork", isDirectory: true)
        ]

        for baseDirectory in baseDirectories.compactMap({ $0 }) {
            for relativePath in relativeCandidates {
                let candidate = baseDirectory.appendingPathComponent(relativePath, isDirectory: false)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        return nil
    }

    func updateCurrentPageTitle(_ title: String?) {
        currentPageTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func stopAccessingSecurityScopeIfNeeded() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    func shutdown() {
        stopAutoplay()
        stopAccessingSecurityScopeIfNeeded()
    }

    private func playPlaylistItem(at index: Int, in playlist: SavedPlaylist) {
        guard playlist.items.indices.contains(index),
              let url = URL(string: playlist.items[index].urlString) else {
            statusMessage = "Playlist item is invalid."
            return
        }

        loadRemoteURL(url, status: "Playing playlist: \(playlist.items[index].title)")
    }

    private func restartAutoplayIfPossible() {
        autoplayTimer?.invalidate()
        autoplayTimer = nil

        guard let playlist = selectedPlaylist else {
            statusMessage = "Select a playlist to enable autoplay."
            isAutoplayEnabled = false
            return
        }

        guard !playlist.items.isEmpty else {
            statusMessage = "Add items to the selected playlist before autoplay."
            isAutoplayEnabled = false
            return
        }

        autoplayTimer = Timer.scheduledTimer(withTimeInterval: playlist.intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.playNextPlaylistItem()
            }
        }

        RunLoop.main.add(autoplayTimer!, forMode: .common)
        statusMessage = "Autoplay enabled every \(Int(playlist.intervalSeconds)) sec."
    }

    private func stopAutoplay() {
        autoplayTimer?.invalidate()
        autoplayTimer = nil
        statusMessage = "Autoplay stopped."
    }

    private func persistLibrary() {
        let payload = PersistedLibrary(
            favorites: favorites,
            playlists: playlists,
            selectedPlaylistID: selectedPlaylistID,
            currentArtwork: persistedCurrentArtwork(),
            playerFrameStyle: playerFrameStyle,
            controlPanelOpacity: controlPanelOpacity
        )

        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: persistenceURL, options: [.atomic])
        } catch {
            statusMessage = "Could not save library: \(error.localizedDescription)"
        }
    }

    private func restoreLibrary() {
        guard let data = try? Data(contentsOf: persistenceURL) else { return }

        do {
            let payload = try JSONDecoder().decode(PersistedLibrary.self, from: data)
            favorites = payload.favorites
            playlists = payload.playlists
            selectedPlaylistID = payload.selectedPlaylistID ?? payload.playlists.first?.id
            playerFrameStyle = payload.playerFrameStyle ?? .shell
            controlPanelOpacity = payload.controlPanelOpacity ?? 0.96
            syncPlaylistIntervalInput()
            restoreCurrentArtwork(from: payload.currentArtwork)
        } catch {
            statusMessage = "Could not restore library."
        }
    }

    private func syncPlaylistIntervalInput() {
        playlistIntervalInput = String(Int(selectedPlaylist?.intervalSeconds ?? 20))
    }

    private func uniquePlaylistName(_ baseName: String) -> String {
        guard playlists.contains(where: { $0.name == baseName }) else {
            return baseName
        }

        var suffix = 2
        while playlists.contains(where: { $0.name == "\(baseName) \(suffix)" }) {
            suffix += 1
        }

        return "\(baseName) \(suffix)"
    }

    private func persistedCurrentArtwork() -> PersistedCurrentArtwork? {
        guard let currentSource else { return nil }

        switch currentSource {
        case .remote(let url):
            return PersistedCurrentArtwork(kind: "remote", location: url.absoluteString)
        case .local(let fileURL, _):
            return PersistedCurrentArtwork(kind: "local", location: fileURL.path)
        }
    }

    private func restoreCurrentArtwork(from persisted: PersistedCurrentArtwork?) {
        guard let persisted else { return }

        switch persisted.kind {
        case "remote":
            guard let url = URL(string: persisted.location) else { return }
            currentPageTitle = ""
            currentSource = .remote(url)
            inputText = url.absoluteString
            statusMessage = "Restored last artwork."
        case "local":
            let fileURL = URL(fileURLWithPath: persisted.location)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            currentPageTitle = ""
            currentSource = .local(fileURL: fileURL, accessURL: nil)
            inputText = fileURL.path
            statusMessage = "Restored last artwork."
        default:
            break
        }
    }

    private func normalizedRemoteURL(from string: String) -> URL? {
        guard !string.isEmpty,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        return url
    }

    private func suggestedTitle(for url: URL) -> String {
        if let host = url.host(percentEncoded: false), !host.isEmpty {
            return host
        }

        if !url.lastPathComponent.isEmpty {
            return url.lastPathComponent
        }

        return url.absoluteString
    }
}
