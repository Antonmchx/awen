import SwiftUI
import UniformTypeIdentifiers

private struct PlaylistTransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let playlist: SavedPlaylist

    init(playlist: SavedPlaylist) {
        self.playlist = playlist
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        playlist = try JSONDecoder().decode(SavedPlaylist.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(playlist)
        return .init(regularFileWithContents: data)
    }
}

private enum LinkEditorTarget: Identifiable {
    case favorite(SavedArtworkLink)
    case playlistItem(SavedArtworkLink)

    var id: UUID {
        switch self {
        case .favorite(let link), .playlistItem(let link):
            return link.id
        }
    }

    var link: SavedArtworkLink {
        switch self {
        case .favorite(let link), .playlistItem(let link):
            return link
        }
    }

    var title: String {
        switch self {
        case .favorite:
            return "Edit Favorite"
        case .playlistItem:
            return "Edit Playlist Item"
        }
    }
}

struct ControllerView: View {
    @ObservedObject var appState: AppState
    let isCollapsed: Bool
    let onSetPin: (Bool) -> Void
    let onReload: () -> Void
    let onToggleFullscreen: () -> Void
    let onTakeScreenshot: () -> Void
    let onOpenFavorites: () -> Void
    let onOpenPlaylists: () -> Void
    let onToggleCollapse: () -> Void

    @State private var showingImporter = false
    @State private var isSettingsPresented = false
    @State private var isOpenURLPresented = false

    var body: some View {
        Group {
            if isCollapsed {
                collapsedHeaderSection
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerSection
                        loadSection
                        librarySection
                        statusSection
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 420)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(appState.controlPanelOpacity),
                    Color(nsColor: .underPageBackgroundColor).opacity(appState.controlPanelOpacity * 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.html],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                appState.loadLocalFile(url)
            case .failure(let error):
                appState.statusMessage = "File import failed: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsSheet(
                isPinnedToTop: Binding(
                    get: { appState.isPinnedToTop },
                    set: { onSetPin($0) }
                ),
                playerFrameStyle: Binding(
                    get: { appState.playerFrameStyle },
                    set: { appState.setPlayerFrameStyle($0) }
                ),
                controlPanelOpacity: Binding(
                    get: { appState.controlPanelOpacity },
                    set: { appState.setControlPanelOpacity($0) }
                )
            )
        }
        .sheet(isPresented: $isOpenURLPresented) {
            OpenURLSheet(inputText: $appState.inputText) {
                appState.loadRemoteURL()
            }
        }
    }

    private var collapsedHeaderSection: some View {
        HStack(spacing: 10) {
            Text("awen")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Text(appState.currentArtworkTitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            PlainIconButton(systemName: "chevron.down") {
                onToggleCollapse()
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("awen")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))

                    PlainIconButton(systemName: "chevron.up") {
                        onToggleCollapse()
                    }
                }

                Text(appState.currentArtworkTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    IconActionButton(systemName: "arrow.clockwise", action: onReload)
                    IconActionButton(systemName: "arrow.up.left.and.arrow.down.right", action: onToggleFullscreen)
                    IconActionButton(systemName: "camera", action: onTakeScreenshot)
                    CompositeIconActionButton(action: {
                        appState.addCurrentURLToFavorites()
                    }) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(systemName: "heart")
                                .font(.system(size: 12, weight: .semibold))

                            Image(systemName: "plus.circle")
                                .font(.system(size: 8, weight: .semibold))
                                .offset(x: 3, y: 2)
                        }
                    }
                }
            }

            Spacer()

            PlainIconButton(systemName: "gearshape") {
                isSettingsPresented = true
            }
        }
    }

    private var loadSection: some View {
        HStack(spacing: 10) {
            Button("Open URL") {
                isOpenURLPresented = true
            }

            Button("Open File") {
                showingImporter = true
            }
        }
        .buttonStyle(.bordered)
    }

    private var librarySection: some View {
        HStack(spacing: 10) {
            PlainIconButton(systemName: "heart.fill") {
                onOpenFavorites()
            }

            PlainIconButton(systemName: "list.bullet") {
                onOpenPlaylists()
            }
        }
    }

    private var statusSection: some View {
        Text(appState.statusMessage)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.04))
            )
    }
}

struct FavoritesWindowView: View {
    @ObservedObject var appState: AppState
    @State private var editingTarget: LinkEditorTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Favorites")
                    .font(.system(size: 18, weight: .semibold))

                if appState.favorites.isEmpty {
                    PlaceholderCard(text: "No favorites yet.")
                } else {
                    ForEach(appState.favorites) { favorite in
                        CompactLinkRow(
                            title: favorite.title,
                            onPlay: { appState.playFavorite(favorite) },
                            onEdit: { editingTarget = .favorite(favorite) },
                            onDelete: { appState.removeFavorite(favorite.id) }
                        )
                    }
                }
            }
            .padding(16)
        }
        .frame(minWidth: 360, minHeight: 220)
        .sheet(item: $editingTarget) { target in
            LinkEditorSheet(
                title: target.title,
                initialLink: target.link
            ) { updatedTitle, updatedURL in
                switch target {
                case .favorite(let link):
                    return appState.updateFavorite(link.id, title: updatedTitle, urlString: updatedURL)
                case .playlistItem:
                    return false
                }
            }
        }
    }
}

struct PlaylistsWindowView: View {
    @ObservedObject var appState: AppState
    @State private var editingTarget: LinkEditorTarget?
    @State private var isPlaylistItemsExpanded = true
    @State private var showingImporter = false
    @State private var exportDocument: PlaylistTransferDocument?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Playlists")
                    .font(.system(size: 18, weight: .semibold))

                HStack(spacing: 10) {
                    TextField("New playlist", text: $appState.draftPlaylistName)
                        .textFieldStyle(.roundedBorder)

                    Button("Create") {
                        appState.createPlaylist()
                    }
                }

                if appState.playlists.isEmpty {
                    PlaceholderCard(text: "No playlists yet.")
                } else {
                    HStack(spacing: 10) {
                        Button("Import") {
                            showingImporter = true
                        }

                        Button("Export") {
                            guard let selectedPlaylist = appState.selectedPlaylist else { return }
                            exportDocument = PlaylistTransferDocument(playlist: selectedPlaylist)
                        }
                        .disabled(appState.selectedPlaylist == nil)
                    }
                    .buttonStyle(.bordered)

                    Picker("Playlist", selection: Binding(
                        get: { appState.selectedPlaylistID ?? appState.playlists.first?.id },
                        set: { appState.selectPlaylist($0) }
                    )) {
                        ForEach(appState.playlists) { playlist in
                            Text(playlist.name).tag(Optional(playlist.id))
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 10) {
                        Button("Add Current URL") {
                            appState.addCurrentURLToSelectedPlaylist()
                        }

                        Button("Play Now") {
                            appState.playSelectedPlaylistNow()
                        }

                        IconActionButton(systemName: "forward.fill") {
                            appState.playNextPlaylistItem()
                        }

                        if let selectedPlaylist = appState.selectedPlaylist {
                            Button("Delete List") {
                                appState.deletePlaylist(selectedPlaylist.id)
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    HStack(spacing: 10) {
                        Text("Seconds")
                            .font(.system(size: 12))

                        TextField("20", text: $appState.playlistIntervalInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .onSubmit {
                                appState.applySelectedPlaylistIntervalInput()
                            }

                        Button("Set") {
                            appState.applySelectedPlaylistIntervalInput()
                        }

                        Toggle("Autoplay", isOn: Binding(
                            get: { appState.isAutoplayEnabled },
                            set: { appState.setAutoplayEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .frame(width: 110)
                    }

                    if let selectedPlaylist = appState.selectedPlaylist {
                        DisclosureGroup(isExpanded: $isPlaylistItemsExpanded) {
                            VStack(alignment: .leading, spacing: 6) {
                                if selectedPlaylist.items.isEmpty {
                                    PlaceholderCard(text: "Selected playlist is empty.")
                                } else {
                                    ForEach(selectedPlaylist.items) { item in
                                        CompactLinkRow(
                                            title: item.title,
                                            onPlay: { appState.playFavorite(item) },
                                            onEdit: { editingTarget = .playlistItem(item) },
                                            onDelete: { appState.removeItemFromSelectedPlaylist(item.id) }
                                        )
                                    }
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack {
                                Text("Items")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                Spacer()
                                Text("\(selectedPlaylist.items.count)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.06))
                                    )
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(minWidth: 420, minHeight: 320)
        .sheet(item: $editingTarget) { target in
            LinkEditorSheet(
                title: target.title,
                initialLink: target.link
            ) { updatedTitle, updatedURL in
                switch target {
                case .favorite:
                    return false
                case .playlistItem(let link):
                    return appState.updateItemInSelectedPlaylist(link.id, title: updatedTitle, urlString: updatedURL)
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                appState.importPlaylist(from: url)
            case .failure(let error):
                appState.statusMessage = "Playlist import failed: \(error.localizedDescription)"
            }
        }
        .fileExporter(
            isPresented: Binding(
                get: { exportDocument != nil },
                set: { if !$0 { exportDocument = nil } }
            ),
            document: exportDocument,
            contentType: .json,
            defaultFilename: appState.selectedPlaylist?.name.replacingOccurrences(of: "/", with: "-") ?? "playlist"
        ) { result in
            switch result {
            case .success:
                appState.statusMessage = "Playlist exported."
            case .failure(let error):
                appState.statusMessage = "Playlist export failed: \(error.localizedDescription)"
            }
            exportDocument = nil
        }
    }
}

private struct CompactLinkRow: View {
    let title: String
    let onPlay: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer()

            PlainIconButton(systemName: "play.fill", iconSize: 10, padding: 3, action: onPlay)
            PlainIconButton(systemName: "pencil", iconSize: 10, padding: 3, action: onEdit)
            PlainIconButton(systemName: "trash", iconSize: 10, padding: 3, action: onDelete)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }
}

private struct PlaceholderCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.03))
            )
    }
}

private struct IconActionButton: View {
    let systemName: String
    var iconSize: CGFloat = 12
    var padding: CGFloat = 3
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
    }
}

private struct CompositeIconActionButton<Icon: View>: View {
    let action: () -> Void
    let icon: Icon

    init(action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) {
        self.action = action
        self.icon = icon()
    }

    var body: some View {
        Button(action: action) {
            icon
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
    }
}

private struct PlainIconButton: View {
    let systemName: String
    var iconSize: CGFloat = 12
    var padding: CGFloat = 3
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
    }
}

private struct LinkEditorSheet: View {
    let title: String
    let initialLink: SavedArtworkLink
    let onSave: (String, String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draftTitle: String
    @State private var draftURL: String

    init(title: String, initialLink: SavedArtworkLink, onSave: @escaping (String, String) -> Bool) {
        self.title = title
        self.initialLink = initialLink
        self.onSave = onSave
        _draftTitle = State(initialValue: initialLink.title)
        _draftURL = State(initialValue: initialLink.urlString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))

            TextField("Title", text: $draftTitle)
                .textFieldStyle(.roundedBorder)

            TextField("https://example.com/artwork", text: $draftURL)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    if onSave(draftTitle, draftURL) {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct SettingsSheet: View {
    @Binding var isPinnedToTop: Bool
    @Binding var playerFrameStyle: PlayerFrameStyle
    @Binding var controlPanelOpacity: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 18, weight: .semibold))

            Toggle("Always on top", isOn: $isPinnedToTop)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 8) {
                Text("Frame")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("Frame", selection: $playerFrameStyle) {
                    Text("Shell").tag(PlayerFrameStyle.shell)
                    Text("2 mm").tag(PlayerFrameStyle.thin)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Panel Opacity")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(controlPanelOpacity * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Slider(value: $controlPanelOpacity, in: 0.35...1.0, step: 0.01)
            }

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 280)
    }
}

private struct OpenURLSheet: View {
    @Binding var inputText: String
    let onOpen: () -> Bool

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Open URL")
                .font(.system(size: 18, weight: .semibold))

            TextField("https://example.com/artwork", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)
                .onSubmit {
                    if onOpen() {
                        dismiss()
                    }
                }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Open") {
                    if onOpen() {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            isFieldFocused = true
        }
    }
}
