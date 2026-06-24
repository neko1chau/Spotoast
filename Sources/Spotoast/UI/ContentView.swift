import SwiftUI

struct NavigateToArtistKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { _ in }
}
struct NavigateToAlbumKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { _ in }
}
extension EnvironmentValues {
    var navigateToArtist: (String) -> Void {
        get { self[NavigateToArtistKey.self] }
        set { self[NavigateToArtistKey.self] = newValue }
    }
    var navigateToAlbum: (String) -> Void {
        get { self[NavigateToAlbumKey.self] }
        set { self[NavigateToAlbumKey.self] = newValue }
    }
}

struct NavState {
    var showingLikedSongs: Bool
    var selectedPlaylistId: String?
    var searchQuery: String
    var selectedArtistId: String?
    var selectedAlbumId: String?
    var showSettings: Bool
    var showQueue: Bool
}

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var player = WebPlayerManager()
    @StateObject private var apiLoader = APILoader()
    @State private var selectedPlaylistId: String?
    @State private var showingLikedSongs = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showFullPlayer = false
    @State private var showSettings = false
    @State private var searchQuery = ""
    @State private var selectedArtistId: String?
    @State private var selectedAlbumId: String?
    @State private var showQueue = false
    @State private var navStack: [NavState] = []
    @State private var playerSettled = false
    @State private var playlistsCollapsed = false
    @State private var settledTask: Task<Void, Never>?
    @AppStorage("playlistGridView") private var playlistGridView = false

    var body: some View {
        Group {
            if authManager.isLoading {
                ContentPulse(symbol: "person.circle", label: "Authenticating")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authManager.isAuthenticated,
                      let token = authManager.accessToken {
                mainContent(token: token)
            } else {
                LoginView()
            }
        }
        .onChange(of: authManager.error) { err in
            if let err {
                alertTitle = "Auth Error"
                alertMessage = err
                showAlert = true
            }
        }
        .onChange(of: apiLoader.error) { err in
            if let err {
                alertTitle = "API Error"
                alertMessage = err
                showAlert = true
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {
                authManager.error = nil
                apiLoader.error = nil
            }
        } message: {
            Text(alertMessage)
        }
    }

    @ViewBuilder
    private func mainContent(token: String) -> some View {
        ZStack {
            if !showFullPlayer {
                VStack(spacing: 0) {
                    NavigationSplitView {
                        sidebar
                            .frame(minWidth: 240)
                    } detail: {
                        if showQueue {
                            QueueView()
                                .environmentObject(player)
                        } else if showSettings {
                            SettingsView {
                                authManager.logout()
                                player.cleanup()
                                showSettings = false
                            }
                            .environmentObject(authManager)
                        } else if let artistId = selectedArtistId {
                            detailWithBack {
                                popNav()
                            } content: {
                                ArtistView(artistId: artistId, onAlbum: { id in withAnimation(.easeInOut(duration: 0.25)) { pushNav(); selectedArtistId = nil; selectedAlbumId = id } })
                                    .environmentObject(apiLoader)
                                    .environmentObject(player)
                            }
                            .transition(.opacity)
                        } else if let albumId = selectedAlbumId {
                            detailWithBack {
                                popNav()
                            } content: {
                                AlbumView(albumId: albumId)
                                    .environmentObject(apiLoader)
                                    .environmentObject(player)
                            }
                            .transition(.opacity)
                        } else if !searchQuery.isEmpty {
                            detailWithBack {
                                if !navStack.isEmpty { popNav() } else { searchQuery = "" }
                            } content: {
                                SearchResultsView(
                                    query: searchQuery,
                                    onArtist: { selectedArtistId = $0 },
                                    onAlbum: { selectedAlbumId = $0 }
                                )
                                .environmentObject(apiLoader)
                                .environmentObject(player)
                            }
                            .transition(.opacity)
                        } else if showingLikedSongs {
                            LikedSongsView()
                                .environmentObject(apiLoader)
                                .environmentObject(player)
                        } else if let id = selectedPlaylistId {
                            PlaylistDetailView(playlistId: id)
                                .environmentObject(apiLoader)
                                .environmentObject(player)
                        } else {
                            emptyState
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.navigateToArtist, { id in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            pushNav()
                            searchQuery = ""
                            selectedPlaylistId = nil
                            showingLikedSongs = false
                            showSettings = false
                            showQueue = false
                            selectedAlbumId = nil
                            selectedArtistId = id
                        }
                    })
                    .environment(\.navigateToAlbum, { id in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            pushNav()
                            searchQuery = ""
                            selectedPlaylistId = nil
                            showingLikedSongs = false
                            showSettings = false
                            showQueue = false
                            selectedArtistId = nil
                            selectedAlbumId = id
                        }
                    })

                    NowPlayingBar(showFullPlayer: $showFullPlayer, showQueue: $showQueue)
                        .environmentObject(player)
                        .frame(height: 64)
                }
                .transition(.opacity)
            }

            if showFullPlayer {
                FullPlayerView(isPresented: $showFullPlayer)
                    .environmentObject(player)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .frame(minHeight: 500)
        .background {
            HiddenWebView(manager: player)
                .frame(width: 1, height: 1)
                .offset(x: -9999)
                .allowsHitTesting(false)
        }
        .onAppear {
            setupPlayer(token: token)
            Task {
                await apiLoader.configure(token: token, authManager: authManager)
                if let api = apiLoader.api {
                    player.api = api
                }
                await apiLoader.loadSavedTracks()
            }
        }
        .onChange(of: player.error) { err in
            if let err {
                alertTitle = "Player Error"
                alertMessage = err
                showAlert = true
            }
        }
        .onChange(of: showAlert) { showing in
            if !showing { player.error = nil }
        }
        .modifier(PlayerKeyboardShortcuts(player: player))
    }

    private func pushNav() {
        navStack.append(NavState(
            showingLikedSongs: showingLikedSongs,
            selectedPlaylistId: selectedPlaylistId,
            searchQuery: searchQuery,
            selectedArtistId: selectedArtistId,
            selectedAlbumId: selectedAlbumId,
            showSettings: showSettings,
            showQueue: showQueue
        ))
    }

    private func popNav() {
        guard let prev = navStack.popLast() else {
            selectedArtistId = nil
            selectedAlbumId = nil
            return
        }
        showingLikedSongs = prev.showingLikedSongs
        selectedPlaylistId = prev.selectedPlaylistId
        searchQuery = prev.searchQuery
        selectedArtistId = prev.selectedArtistId
        selectedAlbumId = prev.selectedAlbumId
        showSettings = prev.showSettings
        showQueue = prev.showQueue
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if let track = player.currentTrack {
                nowPlayingCard(track)
            } else if playerSettled {
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.3))
                Text("Select a playlist to start")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.5))
            } else {
                ContentPulse(symbol: "music.quarternote.3", label: "Connecting to Spotify")
            }
        }
        .animation(.easeOut(duration: 0.35), value: player.currentTrack?.id)
        .animation(.easeOut(duration: 0.35), value: playerSettled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: player.isReady) { ready in
            settledTask?.cancel()
            if ready {
                settledTask = Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if !Task.isCancelled && player.currentTrack == nil {
                        withAnimation(.easeOut(duration: 0.3)) { playerSettled = true }
                    }
                }
            }
        }
        .onChange(of: player.currentTrack?.id) { id in
            if id != nil { playerSettled = true }
        }
    }

    private func nowPlayingCard(_ track: Track) -> some View {
        VStack(spacing: 16) {
            CachedAsyncImage(url: URL(string: track.imageUrl), contentMode: .fit) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
                    .aspectRatio(1, contentMode: .fit)
            }
            .frame(width: 200, height: 200)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)

            VStack(spacing: 4) {
                Text(track.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(track.artists)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.3)) { showFullPlayer = true } }
    }

    private func detailWithBack<Content: View>(action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.25)) { action() } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .padding(.leading, 12)
                .padding(.vertical, 6)
                Spacer()
            }
            content()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField("Search", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onChange(of: searchQuery) { query in
                        selectedPlaylistId = nil
                        showingLikedSongs = false
                        showSettings = false
                        selectedArtistId = nil
                        selectedAlbumId = nil
                        apiLoader.search(query: query)
                    }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)

            List(selection: Binding<String?>(
                get: { showingLikedSongs ? "__liked__" : selectedPlaylistId },
                set: { newValue in
                    showSettings = false
                    showQueue = false
                    searchQuery = ""
                    selectedArtistId = nil
                    selectedAlbumId = nil
                    if newValue == "__liked__" {
                        showingLikedSongs = true
                        selectedPlaylistId = nil
                    } else {
                        showingLikedSongs = false
                        selectedPlaylistId = newValue
                    }
                }
            )) {
                Section {
                    sidebarHeader("Library")

                    Label {
                        Text("Liked Songs")
                    } icon: {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.pink)
                    }
                    .tag("__liked__")

                    HStack(spacing: 4) {
                        Text("Playlists")
                        if playlistsCollapsed {
                            Text("\(apiLoader.playlists.count)")
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                        Spacer()
                        if !playlistsCollapsed {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) { playlistGridView.toggle() }
                            } label: {
                                Image(systemName: playlistGridView ? "list.bullet" : "square.grid.2x2")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.25)) { playlistsCollapsed.toggle() }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if !playlistsCollapsed {
                        if apiLoader.isLoadingPlaylists {
                            Text("Loading...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        }
                        if playlistGridView {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                                ForEach(apiLoader.playlists) { playlist in
                                    VStack(spacing: 5) {
                                        CachedAsyncImage(url: URL(string: playlist.images?.first?.url ?? "")) {
                                            Color.primary.opacity(0.08)
                                        }
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(minWidth: 0, maxWidth: .infinity)
                                        .clipped()
                                        .cornerRadius(6)

                                        Text(playlist.name)
                                            .font(.system(size: 10))
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        showingLikedSongs = false
                                        selectedPlaylistId = playlist.id
                                    }
                                }
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        } else {
                            ForEach(apiLoader.playlists) { playlist in
                                HStack(spacing: 10) {
                                    CachedAsyncImage(url: URL(string: playlist.images?.first?.url ?? "")) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.primary.opacity(0.08))
                                    }
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(playlist.name)
                                            .lineLimit(1)
                                            .font(.system(size: 13))
                                        Text("\(playlist.tracks?.total ?? 0) tracks")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .tag(playlist.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollIndicators(.never)

            Divider()

            HStack {
                Circle()
                    .fill(player.isReady ? Color.green :
                          player.sdkStatus.hasPrefix("Error") ? Color.red : Color.orange)
                    .frame(width: 6, height: 6)
                Text(player.sdkStatus)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                if player.sdkStatus.hasPrefix("Error") || player.sdkStatus.hasPrefix("JS Error") {
                    Button("Reconnect") {
                        player.reconnect()
                        if let token = authManager.accessToken {
                            player.setup(with: token)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.orange)
                }

                Button {
                    showSettings = true
                    showingLikedSongs = false
                    selectedPlaylistId = nil
                } label: {
                    Image(systemName: "gearshape")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func sidebarHeader(_ title: String, count: Int? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 4) {
            Text(title)
            if let count {
                Text("\(count)")
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func setupPlayer(token: String) {
        player.setup(with: token)
        MediaKeyManager.shared.start(player: player)
    }
}

// MARK: - Keyboard Shortcuts

struct PlayerKeyboardShortcuts: ViewModifier {
    @ObservedObject var player: WebPlayerManager

    func body(content: Content) -> some View {
        content
            .background {
                Button("") { player.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                    .frame(width: 0, height: 0).hidden()
                Button("") { player.nextTrack() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .frame(width: 0, height: 0).hidden()
                Button("") { player.previousTrack() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .frame(width: 0, height: 0).hidden()
            }
    }
}

// MARK: - Simple async loader for the view layer

@MainActor
class APILoader: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var playlistTracks: [String: [PlaylistTrack]] = [:]
    @Published var savedTracks: [SavedTrack] = []
    @Published var searchTracks: [TrackItem] = []
    @Published var searchArtists: [ArtistItem] = []
    @Published var searchAlbums: [AlbumItem] = []
    @Published var isSearching = false
    @Published var error: String?
    @Published var isLoadingPlaylists = false
    @Published var isLoadingTracks = false
    @Published var isLoadingSavedTracks = false

    private(set) var api: APIClient?
    private var trackLoadTask: Task<Void, Never>?
    private weak var authManager: AuthManager?

    private let maxCachedPlaylists = 50

    func configure(token: String, authManager: AuthManager) async {
        let client = APIClient(accessToken: token)
        api = client
        self.authManager = authManager

        authManager.onTokenRefresh = { newToken in
            Task { await client.updateToken(newToken) }
        }

        await client.setUnauthorizedHandler { [weak self] in
            guard let self, let authManager = self.authManager else { return false }
            return await authManager.refreshAccessToken()
        }

        Task { await loadPlaylists() }
    }

    func loadPlaylists() async {
        guard let api = api else { return }
        isLoadingPlaylists = true
        do {
            let result = try await loadPlaylistsWithRetry(api: api)
            await PlaylistCache.savePlaylists(result)
            withAnimation(.easeOut(duration: 0.3)) {
                playlists = result
                isLoadingPlaylists = false
            }
        } catch {
            if let cached = await PlaylistCache.loadPlaylists(), !cached.isEmpty {
                withAnimation(.easeOut(duration: 0.3)) {
                    playlists = cached
                    isLoadingPlaylists = false
                }
            } else {
                let detail = (error as? DecodingError).map { String(describing: $0) } ?? error.localizedDescription
                self.error = "Failed to load playlists: \(detail)"
                withAnimation { isLoadingPlaylists = false }
            }
        }
    }

    private func loadPlaylistsWithRetry(api: APIClient) async throws -> [Playlist] {
        do {
            return try await api.getUserPlaylists()
        } catch APIError.unauthorized {
            try await Task.sleep(nanoseconds: 500_000_000)
            return try await api.getUserPlaylists()
        }
    }

    func loadTracks(for playlistId: String) async {
        trackLoadTask?.cancel()
        isLoadingTracks = true
        trackLoadTask = Task { [weak self] in
            defer { Task { @MainActor in self?.isLoadingTracks = false } }

            guard let api = self?.api else { return }
            do {
                let tracks = try await api.getPlaylistTracks(playlistId)
                await PlaylistCache.savePlaylistTracks(tracks, for: playlistId)
                self?.setTracks(tracks, for: playlistId)
            } catch APIError.unauthorized {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let tracks = try? await api.getPlaylistTracks(playlistId) {
                    await PlaylistCache.savePlaylistTracks(tracks, for: playlistId)
                    self?.setTracks(tracks, for: playlistId)
                } else if !Task.isCancelled {
                    self?.error = "Failed to load tracks: retry failed"
                }
            } catch {
                if !Task.isCancelled {
                    if let cached = await PlaylistCache.loadPlaylistTracks(for: playlistId) {
                        self?.setTracks(cached, for: playlistId)
                    } else {
                        self?.error = "Failed to load tracks: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func setTracks(_ tracks: [PlaylistTrack], for playlistId: String) {
        if playlistTracks.count >= maxCachedPlaylists, playlistTracks[playlistId] == nil {
            if let oldestKey = playlistTracks.keys.first {
                playlistTracks.removeValue(forKey: oldestKey)
            }
        }
        playlistTracks[playlistId] = tracks
    }

    func loadSavedTracks() async {
        guard let api = api else { return }
        isLoadingSavedTracks = true
        do {
            let result = try await api.getSavedTracks()
            await PlaylistCache.saveSavedTracks(result)
            withAnimation(.easeOut(duration: 0.3)) {
                savedTracks = result
                isLoadingSavedTracks = false
            }
        } catch {
            if let cached = await PlaylistCache.loadSavedTracks(), !cached.isEmpty {
                withAnimation(.easeOut(duration: 0.3)) {
                    savedTracks = cached
                    isLoadingSavedTracks = false
                }
            } else {
                self.error = "Failed to load Liked Songs: \(error.localizedDescription)"
                withAnimation { isLoadingSavedTracks = false }
            }
        }
    }

    private var searchTask: Task<Void, Never>?

    func search(query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchTracks = []; searchArtists = []; searchAlbums = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let api = self?.api else { return }
            do {
                let result = try await api.search(query: query)
                if !Task.isCancelled {
                    self?.searchTracks = result.tracks?.items ?? []
                    self?.searchArtists = result.artists?.items ?? []
                    self?.searchAlbums = result.albums?.items ?? []
                    self?.isSearching = false
                }
            } catch {
                if !Task.isCancelled {
                    self?.error = "Search failed: \(error.localizedDescription)"
                    self?.isSearching = false
                }
            }
        }
    }
}

