import SwiftUI

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

    var body: some View {
        Group {
            if authManager.isLoading {
                ProgressView("Authenticating...")
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
                        if showingLikedSongs {
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
                    .frame(minWidth: 750, minHeight: 400)

                    NowPlayingBar(showFullPlayer: $showFullPlayer)
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
                .frame(width: 300, height: 300)
                .opacity(0)
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            if !player.isReady {
                ContentPulse(symbol: "wifi", label: "Connecting to Spotify")
            } else {
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("Select a playlist to start")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding<String?>(
                get: { showingLikedSongs ? "__liked__" : selectedPlaylistId },
                set: { newValue in
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
                    Label {
                        HStack {
                            Text("Liked Songs")
                            Spacer()
                            if apiLoader.isLoadingSavedTracks {
                                ProgressView().scaleEffect(0.5)
                            }
                        }
                    } icon: {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.pink)
                    }
                    .tag("__liked__")
                } header: {
                    Text("Library")
                }

                Section {
                    if apiLoader.isLoadingPlaylists {
                        HStack {
                            ProgressView().scaleEffect(0.7)
                            Text("Loading...").foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach(apiLoader.playlists) { playlist in
                        HStack(spacing: 10) {
                            AsyncImage(url: URL(string: playlist.images?.first?.url ?? "")) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.08))
                            }
                            .frame(width: 32, height: 32)
                            .cornerRadius(4)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(playlist.name)
                                    .lineLimit(1)
                                    .font(.system(.body))
                                Text("\(playlist.tracks.total) tracks")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(playlist.id)
                    }
                } header: {
                    Text("Playlists")
                }
            }
            .listStyle(.sidebar)

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

                Button("Logout") {
                    authManager.logout()
                    player.cleanup()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func setupPlayer(token: String) {
        player.setup(with: token)
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
            playlists = try await loadPlaylistsWithRetry(api: api)
            isLoadingPlaylists = false
        } catch {
            let detail: String
            if let decodingError = error as? DecodingError {
                detail = String(describing: decodingError)
            } else {
                detail = error.localizedDescription
            }
            self.error = "Failed to load playlists: \(detail)"
            isLoadingPlaylists = false
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
                self?.setTracks(tracks, for: playlistId)
            } catch APIError.unauthorized {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let tracks = try? await api.getPlaylistTracks(playlistId) {
                    self?.setTracks(tracks, for: playlistId)
                } else if !Task.isCancelled {
                    self?.error = "Failed to load tracks: retry failed"
                }
            } catch {
                if !Task.isCancelled {
                    self?.error = "Failed to load tracks: \(error.localizedDescription)"
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
            savedTracks = try await api.getSavedTracks()
            isLoadingSavedTracks = false
        } catch {
            self.error = "Failed to load Liked Songs: \(error.localizedDescription)"
            isLoadingSavedTracks = false
        }
    }
}
