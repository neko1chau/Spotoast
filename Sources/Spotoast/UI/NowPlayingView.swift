import SwiftUI

// MARK: - Shared Track Row

struct TrackRow: View {
    let track: TrackItem
    let index: Int
    let allTrackIds: [String]
    let isHovered: Bool
    let onHover: (Bool) -> Void
    @EnvironmentObject var player: WebPlayerManager

    var body: some View {
        let isPlaying = player.currentTrack?.id == track.id && !player.isPaused
        let isCurrentTrack = player.currentTrack?.id == track.id

        HStack(spacing: 12) {
            ZStack {
                Text("\(index + 1)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
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

            AsyncImage(url: URL(string: track.album.images.first?.url ?? "")) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
            }
            .frame(width: 36, height: 36)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(.body))
                    .lineLimit(1)
                    .foregroundColor(isCurrentTrack ? .green : .primary)
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
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
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
                    .background(Color.accentColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

}

// MARK: - Now Playing Bottom Bar

struct NowPlayingBar: View {
    @EnvironmentObject var player: WebPlayerManager
    @AppStorage("playerVolume") private var volume: Double = 0.5
    @Binding var showFullPlayer: Bool

    var body: some View {
        VStack(spacing: 0) {
            progressSlider

            HStack(spacing: 0) {
                trackInfo
                    .frame(maxWidth: .infinity, alignment: .leading)
                playbackControls
                    .frame(maxWidth: .infinity)
                volumeControl
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var trackInfo: some View {
        Group {
            if let track = player.currentTrack {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: track.imageUrl)) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
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

    private var progressSlider: some View {
        GeometryReader { geo in
            let progress = player.duration > 0 ? player.position / player.duration : 0
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                Rectangle()
                    .fill(Color.green)
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
        .frame(height: 3)
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

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let leftW = w * 0.44
                let artSize = max(min(h * 0.33, leftW - 80, 300), 60)

                ZStack {
                    Color(nsColor: .init(white: 0.08, alpha: 1))
                    if let track = player.currentTrack {
                        AsyncImage(url: URL(string: track.imageUrl)) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                                .blur(radius: 100).opacity(0.3).scaleEffect(1.5)
                        } placeholder: { EmptyView() }
                    }
                    Color.black.opacity(0.15)

                    VStack(spacing: 16) {
                        albumArt(size: artSize)
                        trackInfo
                        progressBar(width: min(artSize + 40, leftW - 40))
                        playbackControls
                    }
                    .position(x: leftW / 2, y: h / 2)

                    lyricsSide(h: h)
                        .frame(width: w - leftW, height: h)
                        .position(x: leftW + (w - leftW) / 2, y: h / 2)
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: { withAnimation(.easeInOut(duration: 0.3)) { isPresented = false } }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 14)
                    Spacer()
                }
                .padding(.top, 4)
                Spacer()
            }
        }
        .background { ImmersiveTitleBar() }
        .background {
            Button("") { withAnimation(.easeInOut(duration: 0.3)) { isPresented = false } }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 0, height: 0).hidden()
        }
        .onChange(of: player.currentTrack?.id) { _ in player.loadLyricsIfNeeded() }
        .onAppear { player.loadLyricsIfNeeded() }
    }

    // MARK: - Player subviews

    @ViewBuilder
    private func albumArt(size: CGFloat) -> some View {
        if let track = player.currentTrack {
            AsyncImage(url: URL(string: track.imageUrl)) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
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
        let barHeight: CGFloat = isDragging ? 6 : 4

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
            iBtn("backward.fill", sz: 22, c: .white) { player.previousTrack() }
            Button(action: { player.togglePlay() }) {
                Image(systemName: player.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 48))
            }.buttonStyle(.borderless).foregroundColor(.white)
            iBtn("forward.fill", sz: 22, c: .white) { player.nextTrack() }
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
                lyricsScroll(fadeH: fadeH)
            }
        }
    }

    private func lyricsScroll(fadeH: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    Spacer().frame(height: fadeH + 40)
                    ForEach(player.lyrics) { line in
                        let active = player.isSyncedLyrics && line.id == currentLineId
                        Text(line.words)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white.opacity(active ? 1.0 : 0.18))
                            .scaleEffect(active ? 1.08 : 1.0, anchor: .leading)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 4)
                            .id(line.id)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: active)
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
            .onChange(of: currentLineId) { id in
                if let id {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var currentLineId: TimeInterval? {
        guard player.isSyncedLyrics else { return nil }
        var best: LyricLine?
        for line in player.lyrics { if line.startTime <= player.position { best = line } else { break } }
        return best?.id
    }

    private func fmt(_ t: TimeInterval) -> String { "\(Int(t) / 60):\(String(format: "%02d", Int(t) % 60))" }
}

private struct LyricsPulse: View {
    @State private var pulse = false

    var body: some View {
        VStack {
            Spacer()
            Text("♪")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(pulse ? 0.35 : 0.1))
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
            Spacer()
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

private struct ImmersiveTitleBar: NSViewRepresentable {
    class Coordinator {
        weak var window: NSWindow?

        func apply() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.collectionBehavior.insert(.fullScreenPrimary)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            context.coordinator.window = v.window
            context.coordinator.apply()
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.window == nil, let w = nsView.window {
            context.coordinator.window = w
        }
        context.coordinator.apply()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {}
}


