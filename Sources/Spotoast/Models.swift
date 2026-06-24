import Foundation

struct Track: Equatable {
    let id: String
    let name: String
    let artists: String
    let imageUrl: String
}

struct Playlist: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let owner: Owner
    let images: [SpotifyImage]?
    let tracks: TracksRef?

    struct Owner: Codable {
        let displayName: String?
        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }
    struct TracksRef: Codable { let total: Int }
}

struct SpotifyImage: Codable {
    let url: String
    let width: Int?
    let height: Int?
}

struct PlaylistTrack: Codable {
    let track: TrackItem?
}

struct TrackItem: Codable {
    let id: String
    let name: String
    let artists: [Artist]
    let album: Album
    let durationMs: Int

    enum CodingKeys: String, CodingKey {
        case id, name, artists, album
        case durationMs = "duration_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.artists = try container.decodeIfPresent([Artist].self, forKey: .artists) ?? []
        self.album = try container.decodeIfPresent(Album.self, forKey: .album) ?? Album(id: nil, images: [])
        self.durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
    }
}

struct Artist: Codable {
    let id: String?
    let name: String
}

struct Album: Codable {
    let id: String?
    let images: [SpotifyImage]
}


struct SavedTrack: Codable, Identifiable {
    let addedAt: String
    let track: TrackItem

    var id: String { track.id }

    enum CodingKeys: String, CodingKey {
        case addedAt = "added_at"
        case track
    }
}

struct SavedTracksResponse: Codable {
    let items: [SavedTrack]
    let next: String?
    let total: Int
}

// MARK: - Search

struct SearchResult: Codable {
    let tracks: SearchTracks?
    let artists: SearchArtists?
    let albums: SearchAlbums?
}

struct SearchTracks: Codable {
    let items: [TrackItem]
}

struct SearchArtists: Codable {
    let items: [ArtistItem]
}

struct SearchAlbums: Codable {
    let items: [AlbumItem]
}

struct ArtistItem: Codable, Identifiable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
}

struct AlbumItem: Codable, Identifiable {
    let id: String
    let name: String
    let artists: [Artist]
    let images: [SpotifyImage]?
    let releaseDate: String?
    let totalTracks: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, artists, images
        case releaseDate = "release_date"
        case totalTracks = "total_tracks"
    }
}

struct ArtistTopTracksResponse: Codable {
    let tracks: [TrackItem]
}

struct AlbumTracksResponse: Codable {
    let items: [AlbumTrackItem]
}

struct AlbumTrackItem: Codable, Identifiable {
    let id: String
    let name: String
    let artists: [Artist]
    let durationMs: Int
    let trackNumber: Int

    enum CodingKeys: String, CodingKey {
        case id, name, artists
        case durationMs = "duration_ms"
        case trackNumber = "track_number"
    }
}

struct ArtistAlbumsResponse: Codable {
    let items: [AlbumItem]
}

// MARK: - Lyrics (LRCLIB)

struct LrcLibResponse: Codable {
    let syncedLyrics: String?
    let plainLyrics: String?
}

struct LrcLibSearchResult: Codable {
    let syncedLyrics: String?
    let plainLyrics: String?
    let duration: Double?
    let artistName: String?
}

struct LyricLine: Identifiable {
    let startTime: TimeInterval
    let words: String
    var id: TimeInterval { startTime }

    static func parse(lrc: String) -> [LyricLine] {
        lrc.components(separatedBy: "\n").compactMap { line in
            guard line.hasPrefix("["),
                  let closeBracket = line.firstIndex(of: "]") else { return nil }
            let timeStr = String(line[line.index(after: line.startIndex)..<closeBracket])
            let text = String(line[line.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            let parts = timeStr.split(separator: ":")
            guard parts.count == 2,
                  let min = Double(parts[0]),
                  let sec = Double(parts[1]) else { return nil }
            return LyricLine(startTime: min * 60 + sec, words: text)
        }
    }
}

enum RepeatMode: String {
    case off
    case context
    case track
}

