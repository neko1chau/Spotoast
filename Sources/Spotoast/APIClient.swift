import Foundation

actor APIClient {
    private let session = URLSession.shared
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
        guard let url = URL(string: "\(baseURL)/me/player") else { throw APIError.invalidURL("/me/player") }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        let (resData, response) = try await session.data(for: request)
        try checkResponse(resData, response, path: "/me/player")
    }

    func startPlayback(contextUri: String? = nil, uris: [String]? = nil, offset: Int? = nil, deviceId: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let contextUri { body["context_uri"] = contextUri }
        if let uris { body["uris"] = uris }
        if let offset { body["offset"] = ["position": offset] }
        let data = try JSONSerialization.data(withJSONObject: body)
        var urlString = "\(baseURL)/me/player/play"
        if let deviceId { urlString += "?device_id=\(deviceId)" }
        guard let url = URL(string: urlString) else { throw APIError.invalidURL(urlString) }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (resData, response) = try await session.data(for: request)
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

    func getLyrics(trackName: String, artistName: String, durationSec: Int) async throws -> LrcLibResponse? {
        let artist = artistName.components(separatedBy: ", ").first ?? artistName
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: trackName),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: "\(durationSec)")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Spotoast/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(LrcLibResponse.self, from: data)
    }

    // MARK: - Generic helpers

    @discardableResult
    private func checkResponse(_ data: Data, _ response: URLResponse, path: String) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            // Try to refresh token and retry will be handled by the caller.
            Task { await onUnauthorized?() }
            let body = String(data: data, encoding: .utf8) ?? "empty"
            throw APIError.unauthorized(body: body)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "empty"
            throw APIError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
        return httpResponse
    }

    private func get<T: Codable>(_ path: String) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try checkResponse(data, response, path: path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func put(_ path: String) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try checkResponse(data, response, path: path)
    }

    private func post(_ path: String) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
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
