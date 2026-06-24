import WebKit
import SwiftUI

@MainActor
class WebPlayerManager: NSObject, ObservableObject {
    @Published var isReady = false
    @Published var isPaused = true
    @Published var currentTrack: Track?
    @Published var position: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var error: String?
    @Published var sdkStatus: String = "Starting..."
    @Published var isShuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var lyrics: [LyricLine] = []
    @Published var isLoadingLyrics = false
    @Published var isSyncedLyrics = false
    @Published var nextTracks: [Track] = []
    @Published var previousTracks: [Track] = []
    @Published var currentLyricLineId: TimeInterval?
    private var lyricsTrackId: String?
    private var lyricsTask: Task<Void, Never>?

    var deviceId: String?
    /// Set this to route playback commands through APIClient instead of JS.
    weak var api: APIClient? {
        didSet {
            guard api !== oldValue, let api, let did = deviceId, isReady, !didTransferPlayback else { return }
            didTransferPlayback = true
            Task { @MainActor in
                try? await api.transferPlayback(deviceId: did, play: false)
            }
        }
    }
    private var webView: WKWebView!
    private weak var parentView: NSView?
    private var didLoadPage = false
    private var progressTimer: Timer?
    private var processCrashed = false
    private var didTransferPlayback = false
    private var lastToken: String?
    private var playbackTask: Task<Void, Never>?

    override init() {
        super.init()
        webView = Self.makeWebView(handler: self)
        webView.navigationDelegate = self
    }

    private static func makeWebView(handler: WKScriptMessageHandler) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(handler, name: "spotifyBridge")

        let consoleScript = WKUserScript(
            source: """
            (function() {
                var origLog = console.log, origErr = console.error, origWarn = console.warn;
                function send(level, args) {
                    try {
                        window.webkit.messageHandlers.spotifyBridge.postMessage({
                            type: 'console', level: level, message: Array.from(args).join(' ')
                        });
                    } catch(e) {}
                }
                console.log = function() { send('log', arguments); origLog.apply(console, arguments); };
                console.error = function() { send('error', arguments); origErr.apply(console, arguments); };
                console.warn = function() { send('warn', arguments); origWarn.apply(console, arguments); };
                window.onerror = function(msg, url, line) {
                    send('error', ['Uncaught: ' + msg + ' at ' + url + ':' + line]);
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        userContentController.addUserScript(consoleScript)

        config.userContentController = userContentController
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 300), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    deinit {
        progressTimer?.invalidate()
    }

    func cleanup() {
        progressTimer?.invalidate()
        progressTimer = nil
        lastPositionUpdate = nil
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: "spotifyBridge")
        webView?.removeFromSuperview()
    }

    func setup(with token: String) {
        lastToken = token
        if processCrashed {
            logger.warn("WebView process crashed, reconnecting...")
            didLoadPage = false
            processCrashed = false
            isReady = false
            didTransferPlayback = false
            sdkStatus = "Reconnecting..."
            recreateWebView()
        }
        if !didLoadPage {
            didLoadPage = true
            sdkStatus = "Starting..."
            loadPlaybackPage(token: token)
        } else {
            updateToken(token)
        }
    }

    func updateToken(_ token: String) {
        lastToken = token
        let escaped = token
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        evaluate("updateToken('\(escaped)')")
    }

    // MARK: - Playback Control (via APIClient)

    private func isDeviceNotFound(_ error: Error) -> Bool {
        let desc = error.localizedDescription
        return desc.contains("404")
    }

    private func handleDeviceNotFound() {
        logger.warn("Device not found (404), reconnecting...")
        sdkStatus = "Reconnecting..."
        deviceId = nil
        reconnect()
        if let token = lastToken {
            setup(with: token)
        }
    }

    func togglePlay() {
        if let api {
            Task { @MainActor in
                do {
                    if isPaused {
                        try await api.resumePlayback(deviceId: deviceId)
                    } else {
                        try await api.pausePlayback(deviceId: deviceId)
                    }
                } catch {
                    if isDeviceNotFound(error) {
                        handleDeviceNotFound()
                    } else {
                        logger.error("Toggle play failed: \(error.localizedDescription)")
                        self.error = "Toggle play failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            evaluate("togglePlay()")
        }
    }

    func nextTrack() {
        if let api {
            Task { @MainActor in
                do {
                    try await api.nextTrack(deviceId: deviceId)
                } catch {
                    if isDeviceNotFound(error) {
                        handleDeviceNotFound()
                    } else {
                        logger.error("Next track failed: \(error.localizedDescription)")
                        self.error = "Next track failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            evaluate("nextTrack()")
        }
    }

    func previousTrack() {
        if let api {
            Task { @MainActor in
                do {
                    try await api.previousTrack(deviceId: deviceId)
                } catch {
                    if isDeviceNotFound(error) {
                        handleDeviceNotFound()
                    } else {
                        logger.error("Previous track failed: \(error.localizedDescription)")
                        self.error = "Previous track failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            evaluate("previousTrack()")
        }
    }

    func seek(to position: TimeInterval) {
        if let api {
            Task { @MainActor in
                do {
                    try await api.seekTo(positionMs: Int(position * 1000))
                } catch {
                    if isDeviceNotFound(error) { handleDeviceNotFound() }
                    else { self.error = "Seek failed: \(error.localizedDescription)" }
                }
            }
        } else {
            evaluate("seekTo(\(Int(position * 1000)))")
        }
    }

    func setVolume(_ volume: Double) {
        if let api {
            Task { @MainActor in
                do {
                    try await api.setVolume(Int(volume * 100))
                } catch {
                    if isDeviceNotFound(error) { handleDeviceNotFound() }
                    else { self.error = "Volume change failed: \(error.localizedDescription)" }
                }
            }
        } else {
            evaluate("changeVolume(\(max(0, min(1, volume))))")
        }
    }

    func toggleShuffle() {
        if let api {
            let newState = !isShuffled
            Task { @MainActor in
                do {
                    try await api.setShuffle(newState, deviceId: deviceId)
                    isShuffled = newState
                } catch {
                    if isDeviceNotFound(error) { handleDeviceNotFound() }
                    else { self.error = "Shuffle failed: \(error.localizedDescription)" }
                }
            }
        }
    }

    func cycleRepeatMode() {
        if let api {
            let next: RepeatMode
            switch repeatMode {
            case .off: next = .context
            case .context: next = .track
            case .track: next = .off
            }
            Task { @MainActor in
                do {
                    try await api.setRepeatMode(next.rawValue, deviceId: deviceId)
                    repeatMode = next
                } catch {
                    if isDeviceNotFound(error) { handleDeviceNotFound() }
                    else { self.error = "Repeat mode failed: \(error.localizedDescription)" }
                }
            }
        }
    }

    func reorderQueue(from source: IndexSet, to destination: Int) {
        nextTracks.move(fromOffsets: source, toOffset: destination)
        guard let api, let current = currentTrack else { return }
        let uris = [current] .map { "spotify:track:\($0.id)" } + nextTracks.map { "spotify:track:\($0.id)" }
        let savedPosition = position
        Task { @MainActor in
            do {
                let did = try await resolveDevice(api: api)
                try await api.startPlayback(uris: uris, offset: 0, deviceId: did)
                try await api.seekTo(positionMs: Int(savedPosition * 1000))
            } catch {
                if isDeviceNotFound(error) { handleDeviceNotFound() }
            }
        }
    }

    func addToQueue(trackId: String) {
        guard let api else { return }
        Task { @MainActor in
            do {
                try await api.addToQueue(trackId: trackId, deviceId: deviceId)
            } catch {
                if isDeviceNotFound(error) { handleDeviceNotFound() }
                else { self.error = "Add to queue failed: \(error.localizedDescription)" }
            }
        }
    }

    func playTracks(_ trackIds: [String], startIndex: Int = 0) {
        playbackTask?.cancel()
        guard !trackIds.isEmpty else { return }
        if let api {
            let uris = trackIds.map { "spotify:track:\($0)" }
            playbackTask = Task { @MainActor in
                do {
                    let did = try await resolveDevice(api: api)
                    try await api.transferPlayback(deviceId: did, play: false)
                    try await api.startPlayback(uris: uris, offset: startIndex, deviceId: did)
                } catch {
                    if isDeviceNotFound(error) { handleDeviceNotFound() }
                    else { self.error = "Play failed: \(error.localizedDescription)" }
                }
            }
        } else {
            let uris = trackIds.map { "spotify:track:\($0)" }
            playViaJS(offset: startIndex, uris: uris)
        }
    }

    func playPlaylist(_ playlistId: String, offset: Int = 0) {
        playbackTask?.cancel()
        if let api {
            playbackTask = Task { @MainActor in
                do {
                    let did = try await resolveDevice(api: api)
                    try await api.transferPlayback(deviceId: did, play: false)
                    try await api.startPlayback(
                        contextUri: "spotify:playlist:\(playlistId)",
                        offset: offset,
                        deviceId: did
                    )
                } catch {
                    if isDeviceNotFound(error) { handleDeviceNotFound() }
                    else { self.error = "Play failed: \(error.localizedDescription)" }
                }
            }
        } else {
            playViaJS(contextUri: "spotify:playlist:\(playlistId)", offset: offset)
        }
    }

    /// Returns a usable device ID, waiting for the embedded SDK to connect.
    private func resolveDevice(api: APIClient) async throws -> String {
        if let did = deviceId { return did }

        for _ in 0..<20 {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 500_000_000)
            if let did = deviceId { return did }
        }

        throw PlaybackError.noDevice
    }

    enum PlaybackError: LocalizedError {
        case noDevice
        var errorDescription: String? {
            "Web Player failed to connect. Make sure you have Spotify Premium."
        }
    }

    // MARK: - Lyrics

    func loadLyricsIfNeeded() {
        guard let track = currentTrack, let api, track.id != lyricsTrackId else { return }
        guard duration > 0 else { return }
        lyricsTask?.cancel()
        lyricsTrackId = track.id
        lyrics = []
        isSyncedLyrics = false
        currentLyricLineId = nil
        isLoadingLyrics = true
        let trackId = track.id, name = track.name, artist = track.artists, dur = Int(duration)
        let cacheEnabled = UserDefaults.standard.bool(forKey: "cacheLyrics")
        lyricsTask = Task { @MainActor in
            if cacheEnabled, let cached = await LyricsCache.load(trackId: trackId),
               (cached.syncedLyrics != nil && !(cached.syncedLyrics?.isEmpty ?? true)) ||
               (cached.plainLyrics != nil && !(cached.plainLyrics?.isEmpty ?? true)) {
                guard !Task.isCancelled, lyricsTrackId == trackId else { return }
                applyLyrics(cached)
                isLoadingLyrics = false
                return
            }
            let resp = await api.getLyrics(trackName: name, artistName: artist, durationSec: dur)
            guard !Task.isCancelled, lyricsTrackId == trackId else { return }
            isLoadingLyrics = false
            if let resp {
                if cacheEnabled { await LyricsCache.save(resp, trackId: trackId) }
                applyLyrics(resp)
            }
        }
    }

    private func applyLyrics(_ resp: LrcLibResponse) {
        if let s = resp.syncedLyrics, !s.isEmpty {
            lyrics = LyricLine.parse(lrc: s)
            isSyncedLyrics = true
        } else if let p = resp.plainLyrics, !p.isEmpty {
            lyrics = p.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .enumerated()
                .map { LyricLine(startTime: Double($0.offset), words: $0.element) }
            isSyncedLyrics = false
        } else {
            lyrics = []
            isSyncedLyrics = false
        }
        updateCurrentLyricLine()
    }

    func updateCurrentLyricLine() {
        guard isSyncedLyrics else { return }
        var best: LyricLine?
        for line in lyrics {
            if line.startTime <= position { best = line } else { break }
        }
        if best?.id != currentLyricLineId {
            currentLyricLineId = best?.id
        }
    }

    // MARK: - JS fallback

    private func playViaJS(contextUri: String? = nil, offset: Int? = nil, uris: [String]? = nil) {
        var body: [String: Any] = [:]
        if let contextUri { body["context_uri"] = contextUri }
        if let uris { body["uris"] = uris }
        if let offset { body["offset"] = ["position": offset] }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            error = "Failed to serialize play request"
            return
        }
        let escaped = jsonStr.replacingOccurrences(of: "'", with: "\\'")
        evaluate("startPlayback('\(escaped)')")
    }

    private func evaluate(_ script: String) {
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error = error {
                Task { @MainActor in
                    self?.error = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Progress Timer

    private var lastPositionUpdate: Date?

    @objc private func progressTick() {
        guard !isPaused else { return }
        guard position < duration - 1 else {
            progressTimer?.invalidate()
            return
        }
        if let last = lastPositionUpdate {
            position += Date().timeIntervalSince(last)
        }
        lastPositionUpdate = Date()
        updateCurrentLyricLine()
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        lastPositionUpdate = Date()
        progressTimer = Timer.scheduledTimer(
            timeInterval: 0.15,
            target: self,
            selector: #selector(progressTick),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
        lastPositionUpdate = nil
    }

    // MARK: - Page loading

    private func loadPlaybackPage(token: String) {
        guard let htmlURL = Bundle.module.url(forResource: "playback", withExtension: "html"),
              var html = try? String(contentsOf: htmlURL, encoding: .utf8) else {
            error = "Failed to load playback.html"
            return
        }
        let escaped = token.replacingOccurrences(of: "'", with: "\\'")
        html = html.replacingOccurrences(of: "<!--TOKEN-->", with: escaped)
        webView.loadHTMLString(html, baseURL: URL(string: "https://sdk.scdn.co"))
    }

    private func recreateWebView() {
        webView?.removeFromSuperview()
        webView = Self.makeWebView(handler: self)
        webView.navigationDelegate = self
        if let parentView {
            webView.frame = parentView.bounds
            parentView.addSubview(webView)
        }
    }

    func attachToView(_ view: NSView) {
        parentView = view
        webView.frame = view.bounds
        view.addSubview(webView)
    }
}

// MARK: - NSViewRepresentable

struct HiddenWebView: NSViewRepresentable {
    let manager: WebPlayerManager

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            manager.attachToView(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - WKScriptMessageHandler

extension WebPlayerManager: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor in
            self.handleBridgeMessage(message)
        }
    }

    @MainActor
    private func handleBridgeMessage(_ message: WKScriptMessage) {
        guard message.name == "spotifyBridge",
              let body = message.body as? [String: Any] else { return }

        let type = body["type"] as? String ?? ""

        switch type {
        case "ready":
            deviceId = body["deviceId"] as? String
            isReady = true
            sdkStatus = "Ready"
            logger.info("SDK ready, deviceId=\(deviceId ?? "nil")")
            if let api, let did = deviceId, !didTransferPlayback {
                didTransferPlayback = true
                Task { @MainActor in
                    try? await api.transferPlayback(deviceId: did, play: false)
                }
            }

        case "stateChanged":
            let paused = body["paused"] as? Bool ?? true
            isPaused = paused
            position = TimeInterval(body["position"] as? Int ?? 0) / 1000
            duration = TimeInterval(body["duration"] as? Int ?? 0) / 1000
            lastPositionUpdate = paused ? nil : Date()
            if let data = body["track"] as? [String: String] {
                let newTrack = Track(
                    id: data["id"] ?? "",
                    name: data["name"] ?? "",
                    artists: data["artists"] ?? "",
                    imageUrl: data["imageUrl"] ?? ""
                )
                if currentTrack?.id != newTrack.id {
                    logger.info("Track: \(newTrack.name) — \(newTrack.artists)")
                }
                currentTrack = newTrack
            }

            func parseTracks(_ key: String) -> [Track] {
                (body[key] as? [[String: String]])?.map {
                    Track(id: $0["id"] ?? "", name: $0["name"] ?? "",
                          artists: $0["artists"] ?? "", imageUrl: $0["imageUrl"] ?? "")
                } ?? []
            }
            nextTracks = parseTracks("nextTracks")
            previousTracks = parseTracks("previousTracks")

            if paused {
                stopProgressTimer()
            } else {
                startProgressTimer()
            }
            updateCurrentLyricLine()
            MediaKeyManager.shared.updateNowPlaying(
                track: currentTrack, isPaused: paused,
                position: position, duration: duration
            )
            if UserDefaults.standard.bool(forKey: "cacheLyrics") {
                loadLyricsIfNeeded()
            }

        case "error":
            let msg = body["message"] as? String ?? "Unknown error"
            if msg.contains("playback_error") {
                logger.warn("playback_error (non-fatal): \(msg)")
                break
            }
            if msg.contains("Invalid token scopes") || msg.contains("authentication_error") {
                logger.error("SDK auth error (re-login required): \(msg)")
                sdkStatus = "Scope error — please logout and re-login"
                error = "Token scopes outdated. Please logout from Settings and re-login to fix."
                break
            }
            sdkStatus = "Error: \(msg)"
            error = msg
            logger.error("SDK error: \(msg)")

        case "console":
            let level = body["level"] as? String ?? "log"
            let msg = body["message"] as? String ?? ""
            if level == "error" {
                sdkStatus = "JS Error: \(msg.prefix(80))"
                logger.error("JS: \(msg)")
            } else if level == "warn" {
                logger.warn("JS: \(msg)")
            }

        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebPlayerManager: WKNavigationDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            self.error = error.localizedDescription
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in
            self.processCrashed = true
            logger.error("Web player process terminated — playback may not work")
            self.error = "Web player process terminated — playback may not work"
        }
    }

    func reconnect() {
        error = nil
        processCrashed = false
        didLoadPage = false
        isReady = false
        didTransferPlayback = false
        recreateWebView()
    }
}
