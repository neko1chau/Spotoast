import SwiftUI
import MediaPlayer

@main
struct SpotoastApp: App {
    @StateObject private var authManager = AuthManager()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.auto

    var body: some Scene {
        WindowGroup("Spotoast") {
            ContentView()
                .environmentObject(authManager)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear { appearanceMode.apply() }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(authManager)
                .frame(width: 480, height: 520)
        }
    }
}

final class MediaKeyManager {
    static let shared = MediaKeyManager()
    private var configured = false
    weak var player: WebPlayerManager?

    func start(player: WebPlayerManager) {
        self.player = player
        guard !configured else { return }
        configured = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let p = self?.player, p.isPaused else { return }
                p.togglePlay()
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let p = self?.player, !p.isPaused else { return }
                p.togglePlay()
            }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.togglePlay() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.nextTrack() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.previousTrack() }
            return .success
        }

        MPNowPlayingInfoCenter.default().playbackState = .playing
    }

    func updateNowPlaying(track: Track?, isPaused: Bool, position: TimeInterval, duration: TimeInterval) {
        var info = [String: Any]()
        if let track {
            info[MPMediaItemPropertyTitle] = track.name
            info[MPMediaItemPropertyArtist] = track.artists
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
            info[MPNowPlayingInfoPropertyPlaybackRate] = isPaused ? 0.0 : 1.0
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPaused ? .paused : .playing
    }
}
