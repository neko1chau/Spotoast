import Foundation

actor APIClient {
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()
    private let baseURL = "https://api.spotify.com/v1"
    private var accessToken: String
    var onUnauthorized: (() async -> Bool)?

    init(accessToken: String) {
        self.accessToken = accessToken
    }

    func updateToken(_ token: String) {
        accessToken = token
    }

    func setUnauthorizedHandler(_ handler: @escaping () async -> Bool) {
        onUnauthorized = handler
    }

    // MARK: - Playlists

    /// Loads ALL user playlists (handles Spotify pagination automatically).
    func getUserPlaylists(limit: Int = 50) async throws -> [Playlist] {
        var allItems: [Playlist] = []
        var url = "/me/playlists?limit=\(limit)"

        while true {
            let response: PaginatedResponse<Playlist> = try await get(url)
            allItems.append(contentsOf: response.items)
            if let next = response.next, let nextURL = URL(string: next),
               let path = nextURL.absoluteString.range(of: "/v1")?.upperBound {
                url = String(nextURL.absoluteString[path...])
            } else {
                break
            }
        }
        return allItems
    }

    /// Loads ALL tracks for a playlist (handles Spotify pagination automatically).
    func getPlaylistTracks(_ playlistId: String) async throws -> [PlaylistTrack] {
        var allItems: [PlaylistTrack] = []
        var url = "/playlists/\(playlistId)/tracks?limit=50"

        while true {
            try Task.checkCancellation()
            let response: PaginatedResponse<PlaylistTrack> = try await get(url)
            allItems.append(contentsOf: response.items)
            if let next = response.next, let nextURL = URL(string: next),
               let path = nextURL.absoluteString.range(of: "/v1")?.upperBound {
                url = String(nextURL.absoluteString[path...])
            } else {
                break
            }
        }
        return allItems
    }

    // MARK: - Saved Tracks (Liked Songs)

    func getSavedTracks(limit: Int = 50, maxItems: Int = 500) async throws -> [SavedTrack] {
        var allItems: [SavedTrack] = []
        var url = "/me/tracks?limit=\(limit)"

        while allItems.count < maxItems {
            try Task.checkCancellation()
            let response: SavedTracksResponse = try await get(url)
            allItems.append(contentsOf: response.items)
            if let next = response.next, let nextURL = URL(string: next),
               let path = nextURL.absoluteString.range(of: "/v1")?.upperBound {
                url = String(nextURL.absoluteString[path...])
            } else {
                break
            }
        }
        return allItems
    }

    // MARK: - Player (Spotify Connect API)

    func transferPlayback(deviceId: String, play: Bool = false) async throws {
        let body = ["device_ids": [deviceId], "play": play] as [String: Any]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let path = "/me/player"
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        var (resData, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            if let handler = onUnauthorized, await handler() {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                (resData, response) = try await session.data(for: request)
            }
        }
        try checkResponse(resData, response, path: path)
    }

    func startPlayback(contextUri: String? = nil, uris: [String]? = nil, offset: Int? = nil, deviceId: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let contextUri { body["context_uri"] = contextUri }
        if let uris { body["uris"] = uris }
        if let offset { body["offset"] = ["position": offset] }
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var urlString = "\(baseURL)/me/player/play"
        if let deviceId { urlString += "?device_id=\(deviceId)" }
        guard let url = URL(string: urlString) else { throw APIError.invalidURL(urlString) }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        var (resData, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            if let handler = onUnauthorized, await handler() {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                (resData, response) = try await session.data(for: request)
            }
        }
        try checkResponse(resData, response, path: "/me/player/play")
    }

    func pausePlayback(deviceId: String? = nil) async throws {
        var path = "/me/player/pause"
        if let deviceId { path += "?device_id=\(deviceId)" }
        try await put(path)
    }

    func resumePlayback(deviceId: String? = nil) async throws {
        var path = "/me/player/play"
        if let deviceId { path += "?device_id=\(deviceId)" }
        try await put(path)
    }

    func nextTrack(deviceId: String? = nil) async throws {
        var path = "/me/player/next"
        if let deviceId { path += "?device_id=\(deviceId)" }
        try await post(path)
    }

    func previousTrack(deviceId: String? = nil) async throws {
        var path = "/me/player/previous"
        if let deviceId { path += "?device_id=\(deviceId)" }
        try await post(path)
    }

    func seekTo(positionMs: Int) async throws {
        try await put("/me/player/seek?position_ms=\(positionMs)")
    }

    func setVolume(_ volume: Int) async throws {
        try await put("/me/player/volume?volume_percent=\(volume)")
    }

    func setShuffle(_ state: Bool, deviceId: String? = nil) async throws {
        var path = "/me/player/shuffle?state=\(state)"
        if let deviceId { path += "&device_id=\(deviceId)" }
        try await put(path)
    }

    func setRepeatMode(_ mode: String, deviceId: String? = nil) async throws {
        var path = "/me/player/repeat?state=\(mode)"
        if let deviceId { path += "&device_id=\(deviceId)" }
        try await put(path)
    }

    func getLyrics(trackName: String, artistName: String, durationSec: Int) async -> LrcLibResponse? {
        let artist = artistName.components(separatedBy: ", ").first ?? artistName
        let variants = Array(Set([trackName, toTraditional(trackName), toSimplified(trackName)]))

        let result: LrcLibResponse? = await withTaskGroup(of: LrcLibResponse?.self) { group in
            for name in variants {
                group.addTask { await self.fetchLrcLib(path: "/api/get", params: [
                    "track_name": name, "artist_name": artist, "duration": "\(durationSec)"
                ])}
                group.addTask { await self.searchLrcLibBest(trackName: name, artistName: artist) }
                group.addTask { await self.fetchNetEaseLyrics(trackName: name, artistName: artist) }
            }

            var bestPlain: LrcLibResponse?
            for await resp in group {
                guard let resp else { continue }
                if resp.syncedLyrics != nil && !(resp.syncedLyrics?.isEmpty ?? true) {
                    group.cancelAll()
                    return resp
                }
                if bestPlain == nil { bestPlain = resp }
            }
            return bestPlain
        }
        return result
    }

    private func searchLrcLibBest(trackName: String, artistName: String) async -> LrcLibResponse? {
        guard let results = await searchLrcLib(trackName: trackName, artistName: artistName) else { return nil }
        let matched = results.filter {
            ($0.artistName ?? "").localizedCaseInsensitiveContains(artistName) ||
            artistName.localizedCaseInsensitiveContains($0.artistName ?? "")
        }
        if let synced = matched.first(where: { $0.syncedLyrics != nil && !$0.syncedLyrics!.isEmpty }) {
            return LrcLibResponse(syncedLyrics: synced.syncedLyrics, plainLyrics: synced.plainLyrics)
        }
        if let plain = matched.first(where: { $0.plainLyrics != nil }) {
            return LrcLibResponse(syncedLyrics: nil, plainLyrics: plain.plainLyrics)
        }
        return nil
    }

    private func toTraditional(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Hans-Hant" as CFString, false)
        return mutable as String
    }

    private func toSimplified(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Hans-Hant" as CFString, true)
        return mutable as String
    }

    private func fetchLrcLib(path: String, params: [String: String]) async -> LrcLibResponse? {
        var components = URLComponents(string: "https://lrclib.net\(path)")!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Spotoast/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(LrcLibResponse.self, from: data)
    }

    private func searchLrcLib(trackName: String, artistName: String) async -> [LrcLibSearchResult]? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "artist_name", value: artistName)
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Spotoast/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode([LrcLibSearchResult].self, from: data)
    }

    // MARK: - NetEase Lyrics Fallback

    private static let lyricsSession = URLSession(configuration: .ephemeral)

    private func fetchNetEaseLyrics(trackName: String, artistName: String) async -> LrcLibResponse? {
        var searchComponents = URLComponents(string: "https://music.163.com/api/search/get")!
        searchComponents.queryItems = [
            URLQueryItem(name: "s", value: "\(trackName) \(artistName)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let searchURL = searchComponents.url else { return nil }
        var searchReq = URLRequest(url: searchURL)
        searchReq.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        guard let (searchData, searchResp) = try? await Self.lyricsSession.data(for: searchReq),
              let searchHttp = searchResp as? HTTPURLResponse,
              (200...299).contains(searchHttp.statusCode) else { return nil }

        struct NetEaseSearch: Codable {
            struct Result: Codable {
                struct Song: Codable {
                    let id: Int
                    let name: String
                    struct Artist: Codable { let name: String }
                    let artists: [Artist]
                }
                let songs: [Song]?
            }
            let result: Result?
        }

        guard let search = try? JSONDecoder().decode(NetEaseSearch.self, from: searchData),
              let songs = search.result?.songs else { return nil }
        guard let matched = songs.first(where: {
            $0.artists.contains(where: { a in
                a.name.localizedCaseInsensitiveContains(artistName) ||
                artistName.localizedCaseInsensitiveContains(a.name)
            })
        }) else { return nil }
        let songId = matched.id

        guard let lyricURL = URL(string: "https://music.163.com/api/song/lyric?id=\(songId)&lv=1") else { return nil }
        var lyricReq = URLRequest(url: lyricURL)
        lyricReq.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        guard let (lyricData, lyricResp) = try? await Self.lyricsSession.data(for: lyricReq),
              let lyricHttp = lyricResp as? HTTPURLResponse,
              (200...299).contains(lyricHttp.statusCode) else { return nil }

        struct NetEaseLyric: Codable {
            struct Lrc: Codable { let lyric: String? }
            let lrc: Lrc?
        }

        guard let parsed = try? JSONDecoder().decode(NetEaseLyric.self, from: lyricData),
              let lrc = parsed.lrc?.lyric, !lrc.isEmpty else { return nil }

        let hasTiming = lrc.range(of: #"\[\d{1,3}:\d{2}"#, options: .regularExpression) != nil
        return LrcLibResponse(
            syncedLyrics: hasTiming ? lrc : nil,
            plainLyrics: hasTiming ? nil : lrc
        )
    }

    // MARK: - Generic helpers

    @discardableResult
    private func checkResponse(_ data: Data, _ response: URLResponse, path: String) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let status = httpResponse.statusCode
        if status == 401 {
            Task { await onUnauthorized?() }
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logger.error("API 401 \(path): \(body.prefix(200))")
            throw APIError.unauthorized(body: body)
        }
        guard (200...299).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? "empty"
            logger.error("API \(status) \(path): \(body.prefix(200))")
            throw APIError.httpError(statusCode: status, body: body)
        }
        return httpResponse
    }

    func addToQueue(trackId: String, deviceId: String?) async throws {
        var path = "/me/player/queue?uri=spotify:track:\(trackId)"
        if let did = deviceId { path += "&device_id=\(did)" }
        try await post(path)
    }

    func search(query: String, types: String = "track,artist,album", limit: Int = 20) async throws -> SearchResult {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await get("/search?q=\(encoded)&type=\(types)&limit=\(limit)")
    }

    func getArtistTopTracks(_ artistId: String) async throws -> [TrackItem] {
        let response: ArtistTopTracksResponse = try await get("/artists/\(artistId)/top-tracks?market=from_token")
        return response.tracks
    }

    func getArtistAlbums(_ artistId: String) async throws -> [AlbumItem] {
        let response: ArtistAlbumsResponse = try await get("/artists/\(artistId)/albums?include_groups=album,single&limit=50")
        return response.items
    }

    func getAlbumTracks(_ albumId: String) async throws -> [AlbumTrackItem] {
        let response: AlbumTracksResponse = try await get("/albums/\(albumId)/tracks?limit=50")
        return response.items
    }

    func getAlbum(_ albumId: String) async throws -> AlbumItem {
        try await get("/albums/\(albumId)")
    }

    private func get<T: Codable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            if let handler = onUnauthorized, await handler() {
                var retry = URLRequest(url: url)
                retry.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                (data, response) = try await session.data(for: retry)
            }
        }
        try checkResponse(data, response, path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func put(_ path: String) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            if let handler = onUnauthorized, await handler() {
                var retry = URLRequest(url: url)
                retry.httpMethod = "PUT"
                retry.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                (data, response) = try await session.data(for: retry)
            }
        }
        try checkResponse(data, response, path: path)
    }

    private func post(_ path: String) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            if let handler = onUnauthorized, await handler() {
                var retry = URLRequest(url: url)
                retry.httpMethod = "POST"
                retry.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                (data, response) = try await session.data(for: retry)
            }
        }
        try checkResponse(data, response, path: path)
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case invalidURL(String)
    case unauthorized(body: String)
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .invalidURL(let path): return "Invalid URL: \(path)"
        case .unauthorized(let body): return "Token expired (401): \(body.prefix(120))"
        case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(120))"
        }
    }
}

/// Supports next‑page pagination (used by playlist tracks).
private struct PaginatedResponse<T: Codable>: Codable {
    let items: [T]
    let next: String?
}
