import SwiftUI

// MARK: - Shared Track Row

struct TrackRow: View {
    let track: TrackItem
    let index: Int
    let allTrackIds: [String]
    let isHovered: Bool
    let onHover: (Bool) -> Void
    @EnvironmentObject var player: WebPlayerManager
    @Environment(\.navigateToArtist) private var navigateToArtist
    @Environment(\.navigateToAlbum) private var navigateToAlbum

    var body: some View {
        let isPlaying = player.currentTrack?.id == track.id && !player.isPaused
        let isCurrentTrack = player.currentTrack?.id == track.id

        HStack(spacing: 12) {
            ZStack {
                Text("\(index + 1)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .opacity(isHovered || isPlaying ? 0 : 1)

                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if isHovered {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 28)

            CachedAsyncImage(url: URL(string: track.album.images.first?.url ?? "")) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
            }
            .frame(width: 36, height: 36)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(isCurrentTrack ? .green : .primary)
                Group {
                    if let firstArtist = track.artists.first, let artistId = firstArtist.id {
                        Text(track.artists.map(\.name).joined(separator: ", "))
                            .onTapGesture { navigateToArtist(artistId) }
                            .onHover { inside in
                                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                    } else {
                        Text(track.artists.map(\.name).joined(separator: ", "))
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Text(timeString(from: track.durationMs))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { onHover($0) }
        .onTapGesture(count: 2) {
            player.playTracks(allTrackIds, startIndex: index)
        }
        .onTapGesture(count: 1) {}
        .contextMenu {
            Button {
                player.playTracks(allTrackIds, startIndex: index)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            Button {
                player.addToQueue(trackId: track.id)
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }
            Divider()
            if let firstArtist = track.artists.first, let artistId = firstArtist.id {
                Button {
                    navigateToArtist(artistId)
                } label: {
                    Label("Go to Artist", systemImage: "person")
                }
            }
            if let albumId = track.album.id {
                Button {
                    navigateToAlbum(albumId)
                } label: {
                    Label("Go to Album", systemImage: "opticaldisc")
                }
            }
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("https://open.spotify.com/track/\(track.id)", forType: .string)
            } label: {
                Label("Copy Song Link", systemImage: "link")
            }
        }
    }

    private func timeString(from ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

// MARK: - Playlist Detail View

struct PlaylistDetailView: View {
    let playlistId: String
    @EnvironmentObject var loader: APILoader
    @EnvironmentObject var player: WebPlayerManager
    @State private var hoveredIndex: Int?

    var body: some View {
        let tracks = loader.playlistTracks[playlistId] ?? []

        let validTracks = tracks.compactMap { $0.track }

        VStack(spacing: 0) {
            if loader.isLoadingTracks && tracks.isEmpty {
                Spacer()
                ContentPulse(symbol: "music.note", label: "Loading tracks")
                Spacer()
            } else if validTracks.isEmpty {
                Spacer()
                Image(systemName: "music.note")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No tracks")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                Spacer()
            } else {
                trackListHeader(count: validTracks.count, onPlayAll: {
                    let ids = validTracks.map(\.id)
                    player.playTracks(ids)
                })

                Divider().padding(.horizontal)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        let ids = validTracks.map(\.id)
                        ForEach(Array(validTracks.enumerated()), id: \.offset) { index, item in
                            TrackRow(
                                track: item,
                                index: index,
                                allTrackIds: ids,
                                isHovered: hoveredIndex == index,
                                onHover: { hoveredIndex = $0 ? index : nil }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: playlistId) {
            if tracks.isEmpty { await loader.loadTracks(for: playlistId) }
        }
    }

    private func trackListHeader(count: Int, onPlayAll: @escaping () -> Void) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                if let playlist = loader.playlists.first(where: { $0.id == playlistId }) {
                    Text(playlist.name)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Text("\(count) tracks")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onPlayAll) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.green)
                    .clipShape(Circle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

}

// MARK: - Search Results View

struct SearchResultsView: View {
    let query: String
    var onArtist: (String) -> Void
    var onAlbum: (String) -> Void
    @EnvironmentObject var loader: APILoader
    @EnvironmentObject var player: WebPlayerManager
    @State private var hoveredIndex: Int?

    var body: some View {
        let hasResults = !loader.searchTracks.isEmpty || !loader.searchArtists.isEmpty || !loader.searchAlbums.isEmpty

        VStack(spacing: 0) {
            if loader.isSearching && !hasResults {
                Spacer()
                ContentPulse(symbol: "magnifyingglass", label: "Searching")
                Spacer()
            } else if !hasResults {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.3))
                Text("No results for \"\(query)\"")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !loader.searchArtists.isEmpty {
                            searchSection("Artists") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(loader.searchArtists.prefix(8)) { artist in
                                            artistCard(artist)
                                                .onTapGesture { onArtist(artist.id) }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        if !loader.searchAlbums.isEmpty {
                            searchSection("Albums") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(loader.searchAlbums.prefix(8)) { album in
                                            albumCard(album)
                                                .onTapGesture { onAlbum(album.id) }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        if !loader.searchTracks.isEmpty {
                            searchSection("Tracks") {
                                let ids = loader.searchTracks.map(\.id)
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(loader.searchTracks.enumerated()), id: \.offset) { index, item in
                                        TrackRow(
                                            track: item,
                                            index: index,
                                            allTrackIds: ids,
                                            isHovered: hoveredIndex == index,
                                            onHover: { hoveredIndex = $0 ? index : nil }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func searchSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            content()
        }
    }

    private func artistCard(_ artist: ArtistItem) -> some View {
        VStack(spacing: 6) {
            CachedAsyncImage(url: URL(string: artist.images?.first?.url ?? "")) {
                Circle().fill(Color.primary.opacity(0.08))
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())

            Text(artist.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 80)
        }
        .contentShape(Rectangle())
    }

    private func albumCard(_ album: AlbumItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CachedAsyncImage(url: URL(string: album.images?.first?.url ?? "")) {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08))
            }
            .frame(width: 100, height: 100)
            .cornerRadius(6)

            Text(album.name)
                .font(.caption)
                .lineLimit(1)
            Text(album.artists.map(\.name).joined(separator: ", "))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 100)
        .contentShape(Rectangle())
    }
}

// MARK: - Artist View

struct ArtistView: View {
    let artistId: String
    var onAlbum: ((String) -> Void)?
    @EnvironmentObject var loader: APILoader
    @EnvironmentObject var player: WebPlayerManager
    @State private var artist: ArtistItem?
    @State private var topTracks: [TrackItem] = []
    @State private var albums: [AlbumItem] = []
    @State private var hoveredIndex: Int?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let artist {
                    artistHeader(artist)
                }

                if !topTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Top Tracks")
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal)

                        let ids = topTracks.map(\.id)
                        LazyVStack(spacing: 0) {
                            ForEach(Array(topTracks.enumerated()), id: \.offset) { index, item in
                                TrackRow(
                                    track: item,
                                    index: index,
                                    allTrackIds: ids,
                                    isHovered: hoveredIndex == index,
                                    onHover: { hoveredIndex = $0 ? index : nil }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Albums")
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], spacing: 16) {
                            ForEach(albums) { album in
                                VStack(alignment: .leading, spacing: 4) {
                                    CachedAsyncImage(url: URL(string: album.images?.first?.url ?? "")) {
                                        RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08))
                                            .aspectRatio(1, contentMode: .fit)
                                    }
                                    .cornerRadius(6)

                                    Text(album.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(album.releaseDate?.prefix(4) ?? "")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { onAlbum?(album.id) }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isLoading {
                ContentPulse(symbol: "person", label: "Loading artist")
            }
        }
        .task(id: artistId) { await loadArtist() }
    }

    private func artistHeader(_ artist: ArtistItem) -> some View {
        HStack(spacing: 16) {
            CachedAsyncImage(url: URL(string: artist.images?.first?.url ?? "")) {
                Circle().fill(Color.primary.opacity(0.08))
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.title2)
                    .fontWeight(.bold)

                if !topTracks.isEmpty {
                    Button {
                        player.playTracks(topTracks.map(\.id))
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private func loadArtist() async {
        guard let api = loader.api else { return }
        isLoading = true
        do {
            async let tracksReq = api.getArtistTopTracks(artistId)
            async let albumsReq = api.getArtistAlbums(artistId)
            let (t, a) = try await (tracksReq, albumsReq)
            topTracks = t
            albums = a
            if let first = loader.searchArtists.first(where: { $0.id == artistId }) {
                artist = first
            } else {
                artist = ArtistItem(id: artistId, name: t.first?.artists.first?.name ?? "", images: nil)
            }
        } catch {
            loader.error = "Failed to load artist: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

// MARK: - Album View

struct AlbumView: View {
    let albumId: String
    @EnvironmentObject var loader: APILoader
    @EnvironmentObject var player: WebPlayerManager
    @State private var album: AlbumItem?
    @State private var tracks: [AlbumTrackItem] = []
    @State private var hoveredIndex: Int?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let album {
                    albumHeader(album)
                    Divider().padding(.horizontal)
                }

                if !tracks.isEmpty {
                    LazyVStack(spacing: 0) {
                        let ids = tracks.map(\.id)
                        ForEach(Array(tracks.enumerated()), id: \.offset) { index, item in
                            albumTrackRow(item, index: index, allIds: ids)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isLoading {
                ContentPulse(symbol: "opticaldisc", label: "Loading album")
            }
        }
        .task(id: albumId) { await loadAlbum() }
    }

    private func albumHeader(_ album: AlbumItem) -> some View {
        HStack(spacing: 16) {
            CachedAsyncImage(url: URL(string: album.images?.first?.url ?? "")) {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08))
            }
            .frame(width: 120, height: 120)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(album.artists.map(\.name).joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let date = album.releaseDate {
                    Text(date.prefix(4))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button {
                    player.playTracks(tracks.map(\.id))
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.green)
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private func albumTrackRow(_ track: AlbumTrackItem, index: Int, allIds: [String]) -> some View {
        let isPlaying = player.currentTrack?.id == track.id && !player.isPaused

        return HStack(spacing: 12) {
            ZStack {
                Text("\(track.trackNumber)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .opacity(hoveredIndex == index || isPlaying ? 0 : 1)

                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption).foregroundColor(.green)
                } else if hoveredIndex == index {
                    Image(systemName: "play.fill")
                        .font(.caption).foregroundColor(.primary)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundColor(player.currentTrack?.id == track.id ? .green : .primary)
                Text(track.artists.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(timeString(from: track.durationMs))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(hoveredIndex == index ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { hoveredIndex = $0 ? index : nil }
        .onTapGesture(count: 2) { player.playTracks(allIds, startIndex: index) }
        .onTapGesture(count: 1) {}
        .contextMenu {
            Button {
                player.playTracks(allIds, startIndex: index)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            Button {
                player.addToQueue(trackId: track.id)
            } label: {
                Label("Add to Queue", systemImage: "text.badge.plus")
            }
            Divider()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("https://open.spotify.com/track/\(track.id)", forType: .string)
            } label: {
                Label("Copy Song Link", systemImage: "link")
            }
        }
    }

    private func timeString(from ms: Int) -> String {
        "\(ms / 60000):\(String(format: "%02d", (ms / 1000) % 60))"
    }

    private func loadAlbum() async {
        guard let api = loader.api else { return }
        isLoading = true
        do {
            async let albumReq = api.getAlbum(albumId)
            async let tracksReq = api.getAlbumTracks(albumId)
            let (a, t) = try await (albumReq, tracksReq)
            album = a
            tracks = t
        } catch {
            loader.error = "Failed to load album: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

// MARK: - Liked Songs View

struct LikedSongsView: View {
    @EnvironmentObject var loader: APILoader
    @EnvironmentObject var player: WebPlayerManager
    @State private var hoveredIndex: Int?

    var body: some View {
        let tracks = loader.savedTracks
        let allIds = tracks.map(\.track.id)

        VStack(spacing: 0) {
            if loader.isLoadingSavedTracks && tracks.isEmpty {
                Spacer()
                ContentPulse(symbol: "heart", label: "Loading liked songs")
                Spacer()
            } else if tracks.isEmpty {
                Spacer()
                Image(systemName: "heart")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No liked songs yet")
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                Spacer()
            } else {
                likedSongsHeader(count: tracks.count)
                Divider().padding(.horizontal)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { index, item in
                            TrackRow(
                                track: item.track,
                                index: index,
                                allTrackIds: allIds,
                                isHovered: hoveredIndex == index,
                                onHover: { hoveredIndex = $0 ? index : nil }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if tracks.isEmpty { await loader.loadSavedTracks() }
        }
    }

    private func likedSongsHeader(count: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Liked Songs")
                    .font(.title2)
                    .fontWeight(.bold)
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.pink)
                    Text("\(count) songs")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                let ids = loader.savedTracks.map(\.track.id)
                player.playTracks(ids)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.green)
                    .clipShape(Circle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

}

// MARK: - Now Playing Bottom Bar

struct NowPlayingBar: View {
    @EnvironmentObject var player: WebPlayerManager
    @AppStorage("playerVolume") private var volume: Double = 0.5
    @Binding var showFullPlayer: Bool
    @Binding var showQueue: Bool

    var body: some View {
        VStack(spacing: 0) {
            progressSlider

            HStack(spacing: 0) {
                trackInfo
                    .frame(maxWidth: .infinity, alignment: .leading)
                playbackControls
                    .frame(maxWidth: .infinity)
                HStack(spacing: 12) {
                    Button { MiniPlayerController.shared.toggle(player: player) } label: {
                        Image(systemName: "pip")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)

                    Button { showQueue.toggle() } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(showQueue ? .accentColor : .secondary)

                    volumeControl
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .glassMaterial()
    }

    private var trackInfo: some View {
        Group {
            if let track = player.currentTrack {
                HStack(spacing: 12) {
                    CachedAsyncImage(url: URL(string: track.imageUrl)) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.08))
                    }
                    .frame(width: 44, height: 44)
                    .cornerRadius(6)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.3)) { showFullPlayer = true } }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .font(.system(.body, weight: .medium))
                            .lineLimit(1)
                        Text(track.artists)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.3)) { showFullPlayer = true } }
            } else {
                Color.clear.frame(height: 44)
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button(action: { player.toggleShuffle() }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundColor(player.isShuffled ? .green : .secondary)

            Button(action: { player.previousTrack() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.primary)

            Button(action: { player.togglePlay() }) {
                Image(systemName: player.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 32))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.primary)

            Button(action: { player.nextTrack() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.primary)

            Button(action: { player.cycleRepeatMode() }) {
                Image(systemName: player.repeatMode == .track ? "repeat.1" : "repeat")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundColor(player.repeatMode != .off ? .green : .secondary)
        }
    }

    @State private var barHovered = false

    private var progressSlider: some View {
        GeometryReader { geo in
            let progress = player.duration > 0 ? player.position / player.duration : 0
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(barHovered ? 0.12 : 0.04))
                Rectangle()
                    .fill(Color.green.opacity(barHovered ? 1.0 : 0.4))
                    .frame(width: geo.size.width * progress)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let fraction = value.location.x / geo.size.width
                        let pos = max(0, min(player.duration, player.duration * fraction))
                        player.seek(to: pos)
                    }
            )
        }
        .frame(height: barHovered ? 5 : 3)
        .onHover { barHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: barHovered)
    }

    @State private var volumeHovered = false

    private var volumeControl: some View {
        HStack(spacing: 6) {
            Image(systemName: volume > 0 ? "speaker.fill" : "speaker.slash.fill")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 14)
            GeometryReader { geo in
                let barH: CGFloat = volumeHovered ? 5 : 3
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: geo.size.width * volume)
                }
                .frame(height: barH)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        volume = max(0, min(1, v.location.x / geo.size.width))
                        player.setVolume(volume)
                    }
                )
                .onHover { volumeHovered = $0 }
                .animation(.easeOut(duration: 0.15), value: volumeHovered)
            }
            .frame(width: 80, height: 16)
        }
    }
}

// MARK: - Full Player View

struct FullPlayerView: View {
    @EnvironmentObject var player: WebPlayerManager
    @Binding var isPresented: Bool
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var scrolledLineId: TimeInterval?

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let leftW = w * 0.44
                let artSize = max(min(h * 0.42, leftW * 0.65, 360), 60)

                ZStack {
                    Color(nsColor: .init(white: 0.08, alpha: 1))
                    if let track = player.currentTrack {
                        AsyncImage(url: URL(string: track.imageUrl), transaction: Transaction(animation: .easeOut(duration: 0.5))) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                                    .blur(radius: 100).opacity(0.3).scaleEffect(1.5)
                            }
                        }
                    }
                    Color.black.opacity(0.15)

                    VStack(spacing: 16) {
                        albumArt(size: artSize)
                        trackInfo
                        progressBar(width: min(artSize + 40, leftW - 40))
                        playbackControls
                    }
                    .position(x: leftW / 2, y: h / 2)
                    .animation(nil, value: player.isLoadingLyrics)
                    .animation(nil, value: player.lyrics.count)

                    lyricsSide(h: h)
                        .frame(width: w - leftW, height: h)
                        .position(x: leftW + (w - leftW) / 2, y: h / 2)
                        .animation(nil, value: player.isLoadingLyrics)
                        .animation(nil, value: player.lyrics.count)
                        .animation(nil, value: player.isSyncedLyrics)
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: { withAnimation(.easeInOut(duration: 0.3)) { isPresented = false } }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 30, height: 30)
                            .glassBackground(cornerRadius: 15, fallback: Color.white.opacity(0.15))
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 14)
                    Spacer()
                }
                .padding(.top, 4)
                Spacer()
            }
        }
        .background {
            Button("") { withAnimation(.easeInOut(duration: 0.3)) { isPresented = false } }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0).hidden()
        }
        .onChange(of: player.currentTrack?.id) { _ in player.loadLyricsIfNeeded() }
        .onChange(of: player.duration) { _ in player.loadLyricsIfNeeded() }
        .onAppear {
            player.loadLyricsIfNeeded()
            applyImmersiveTitleBar(true)
        }
        .onDisappear {
            applyImmersiveTitleBar(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if isPresented { applyImmersiveTitleBar(true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if isPresented { applyImmersiveTitleBar(true) }
        }
    }

    // MARK: - Player subviews

    @ViewBuilder
    private func albumArt(size: CGFloat) -> some View {
        if let track = player.currentTrack {
            CachedAsyncImage(url: URL(string: track.imageUrl), contentMode: .fit) {
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08))
                    .aspectRatio(1, contentMode: .fit)
            }
            .frame(width: size, height: size)
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.5), radius: 20)
        }
    }

    @ViewBuilder
    private var trackInfo: some View {
        if let track = player.currentTrack {
            VStack(spacing: 2) {
                Text(track.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white).lineLimit(1)
                Text(track.artists)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6)).lineLimit(1)
            }
        }
    }

    private func progressBar(width: CGFloat) -> some View {
        let pct = isDragging ? dragProgress : (player.duration > 0 ? min(player.position / player.duration, 1) : 0)
        let barHeight: CGFloat = isDragging ? 8 : 6

        return VStack(spacing: 2) {
            GeometryReader { bar in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(Color.white).frame(width: bar.size.width * pct)
                }
                .frame(height: barHeight)
                .position(x: bar.size.width / 2, y: bar.size.height / 2)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        isDragging = true
                        dragProgress = max(0, min(1, v.location.x / bar.size.width))
                    }
                    .onEnded { v in
                        let fraction = max(0, min(1, v.location.x / bar.size.width))
                        dragProgress = fraction
                        player.seek(to: player.duration * fraction)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isDragging = false
                        }
                    }
                )
            }
            .frame(height: 16)
            HStack {
                Text(fmt(isDragging ? player.duration * dragProgress : player.position))
                Spacer()
                Text(fmt(player.duration))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white.opacity(0.4))
        }
        .frame(width: min(width, 340))
        .animation(.easeOut(duration: 0.15), value: isDragging)
    }

    private var playbackControls: some View {
        HStack(spacing: 26) {
            iBtn("shuffle", sz: 16, c: player.isShuffled ? .green : .white.opacity(0.4)) { player.toggleShuffle() }
            iBtn("backward.fill", sz: 26, c: .white) { player.previousTrack() }
            Button(action: { player.togglePlay() }) {
                Image(systemName: player.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 52))
            }.buttonStyle(.borderless).foregroundColor(.white)
            iBtn("forward.fill", sz: 26, c: .white) { player.nextTrack() }
            iBtn(player.repeatMode == .track ? "repeat.1" : "repeat", sz: 16,
                 c: player.repeatMode != .off ? .green : .white.opacity(0.4)) { player.cycleRepeatMode() }
        }
    }

    private func iBtn(_ n: String, sz: CGFloat, c: Color, a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: n).font(.system(size: sz)) }
            .buttonStyle(.borderless).foregroundColor(c)
    }

    // MARK: - Lyrics side

    private func lyricsSide(h: CGFloat) -> some View {
        let fadeH = max(h * 0.12, 60.0)

        return Group {
            if player.isLoadingLyrics {
                LyricsPulse()
                    .frame(maxWidth: .infinity)
            } else if player.lyrics.isEmpty {
                VStack {
                    Spacer()
                    Text("No lyrics available")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.2))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    if !player.isSyncedLyrics {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.badge.xmark")
                                .font(.system(size: 11))
                            Text("No timeline available")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    }
                    lyricsScroll(fadeH: fadeH)
                }
            }
        }
        .transaction { $0.animation = nil }
    }

    private func lyricsScroll(fadeH: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    Spacer().frame(height: fadeH + 40)
                    ForEach(player.lyrics) { line in
                        let active = player.isSyncedLyrics && line.id == scrolledLineId
                        Text(line.words)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white.opacity(active ? 1.0 : 0.18))
                            .scaleEffect(active ? 1.08 : 1.0, anchor: .leading)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 4)
                            .id(line.id)
                    }
                    Spacer().frame(height: fadeH + 80)
                }
            }
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                        .frame(height: fadeH)
                    Color.white
                    LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: fadeH)
                }
            )
            .onChange(of: player.position) { _ in
                guard player.isSyncedLyrics else { return }
                var best: LyricLine?
                for line in player.lyrics {
                    if line.startTime <= player.position { best = line } else { break }
                }
                guard let id = best?.id, id != scrolledLineId else { return }
                scrolledLineId = id
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: player.lyrics.count) { _ in
                scrolledLineId = nil
            }
        }
    }

    // MARK: - Helpers

    private func fmt(_ t: TimeInterval) -> String { "\(Int(t) / 60):\(String(format: "%02d", Int(t) % 60))" }

    private func applyImmersiveTitleBar(_ immersive: Bool) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: { $0.title == "Spotoast" }) ?? NSApplication.shared.windows.first else { return }
            window.titlebarAppearsTransparent = immersive
            window.titleVisibility = immersive ? .hidden : .visible
            window.titlebarSeparatorStyle = immersive ? .none : .automatic
            if immersive {
                window.styleMask.insert(.fullSizeContentView)
            } else {
                window.styleMask.remove(.fullSizeContentView)
            }
        }
    }
}

// MARK: - Queue View

struct QueueView: View {
    @EnvironmentObject var player: WebPlayerManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider().padding(.horizontal)

            if player.currentTrack == nil && player.nextTracks.isEmpty {
                Spacer()
                Image(systemName: "list.bullet")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.3))
                Text("Queue is empty")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.top, 8)
                Spacer()
            } else {
                List {
                    if let current = player.currentTrack {
                        Section {
                            queueRow(current, isPlaying: true)
                        } header: {
                            Text("Now Playing")
                        }
                    }

                    if !player.nextTracks.isEmpty {
                        Section {
                            ForEach(Array(player.nextTracks.enumerated()), id: \.offset) { _, track in
                                queueRow(track, isPlaying: false)
                            }
                            .onMove { from, to in
                                player.reorderQueue(from: from, to: to)
                            }
                        } header: {
                            Text("Next Up")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func queueRow(_ track: Track, isPlaying: Bool) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: track.imageUrl)) {
                RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08))
            }
            .frame(width: 40, height: 40)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(.body, weight: isPlaying ? .semibold : .regular))
                    .foregroundColor(isPlaying ? .green : .primary)
                    .lineLimit(1)
                Text(track.artists)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()

            if isPlaying && !player.isPaused {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal)
    }
}

private struct LyricsPulse: View {
    @State private var opacity: Double = 0.1

    var body: some View {
        VStack {
            Spacer()
            Text("♪")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(opacity))
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                opacity = 0.35
            }
        }
    }
}

struct ContentPulse: View {
    let symbol: String
    let label: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.6))
        }
    }
}



