import Foundation
import SwiftUI
import CoreImage

// MARK: - Disk Cache

actor DiskCache {
    private let directory: URL

    init(name: String) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = caches.appendingPathComponent("Spotoast/\(name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func read(_ key: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(key))
    }

    func write(_ data: Data, key: String) {
        try? data.write(to: directory.appendingPathComponent(key))
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var sizeBytes: Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

// MARK: - Lyrics Cache

enum LyricsCache {
    static let disk = DiskCache(name: "lyrics")

    static func load(trackId: String) async -> LrcLibResponse? {
        guard let data = await disk.read("\(trackId).json") else { return nil }
        return try? JSONDecoder().decode(LrcLibResponse.self, from: data)
    }

    static func save(_ response: LrcLibResponse, trackId: String) async {
        guard let data = try? JSONEncoder().encode(response) else { return }
        await disk.write(data, key: "\(trackId).json")
    }
}

// MARK: - Playlist Cache

enum PlaylistCache {
    static let disk = DiskCache(name: "playlists")

    static func savePlaylists(_ playlists: [Playlist]) async {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        await disk.write(data, key: "playlists.json")
    }

    static func loadPlaylists() async -> [Playlist]? {
        guard let data = await disk.read("playlists.json") else { return nil }
        return try? JSONDecoder().decode([Playlist].self, from: data)
    }

    static func saveSavedTracks(_ tracks: [SavedTrack]) async {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        await disk.write(data, key: "saved_tracks.json")
    }

    static func loadSavedTracks() async -> [SavedTrack]? {
        guard let data = await disk.read("saved_tracks.json") else { return nil }
        return try? JSONDecoder().decode([SavedTrack].self, from: data)
    }

    static func savePlaylistTracks(_ tracks: [PlaylistTrack], for id: String) async {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        await disk.write(data, key: "tracks_\(id).json")
    }

    static func loadPlaylistTracks(for id: String) async -> [PlaylistTrack]? {
        guard let data = await disk.read("tracks_\(id).json") else { return nil }
        return try? JSONDecoder().decode([PlaylistTrack].self, from: data)
    }
}

// MARK: - Image Cache

enum ImageCache {
    static let disk = DiskCache(name: "images")
    private static let memory: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    static func loadFromMemory(urlString: String) -> NSImage? {
        memory.object(forKey: safeKey(urlString) as NSString)
    }

    static func loadFromDisk(urlString: String) async -> NSImage? {
        let key = safeKey(urlString)
        guard let data = await disk.read(key),
              let image = NSImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    static func saveToMemory(_ image: NSImage, urlString: String) {
        memory.setObject(image, forKey: safeKey(urlString) as NSString)
    }

    static func saveToDisk(_ data: Data, urlString: String) async {
        await disk.write(data, key: safeKey(urlString))
    }

    private static func safeKey(_ url: String) -> String {
        url.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url
    }
}

// MARK: - Cached Async Image

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @AppStorage("cacheCovers") private var cacheEnabled = false
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url?.absoluteString) {
            guard let url else { nsImage = nil; return }
            let urlString = url.absoluteString

            if let cached = ImageCache.loadFromMemory(urlString: urlString) {
                nsImage = cached
                return
            }

            nsImage = nil

            if cacheEnabled, let cached = await ImageCache.loadFromDisk(urlString: urlString) {
                withAnimation(.easeOut(duration: 0.35)) { nsImage = cached }
                return
            }

            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }

            ImageCache.saveToMemory(image, urlString: urlString)
            if cacheEnabled {
                await ImageCache.saveToDisk(data, urlString: urlString)
            }

            withAnimation(.easeOut(duration: 0.35)) { nsImage = image }
        }
    }
}

// MARK: - Average Color

extension NSImage {
    /// Computes the average color of the image via Core Image (downsampled to 1px).
    func averageColor() -> Color? {
        guard let tiff = tiffRepresentation,
              let ciImage = CIImage(data: tiff) else { return nil }
        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        guard let output = filter?.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(output,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: nil)

        return Color(
            .sRGB,
            red: Double(bitmap[0]) / 255,
            green: Double(bitmap[1]) / 255,
            blue: Double(bitmap[2]) / 255,
            opacity: 1
        )
    }
}

/// Loads an image URL and exposes its average color. Confine the colored
/// glow to a small area behind glass so it has something to refract.
@MainActor
final class AlbumColorLoader: ObservableObject {
    @Published var color: Color?
    private var loadedURL: String?

    func load(urlString: String?) {
        guard let urlString, urlString != loadedURL else {
            if urlString == nil { color = nil; loadedURL = nil }
            return
        }
        loadedURL = urlString

        if let cached = ImageCache.loadFromMemory(urlString: urlString) {
            applyColor(from: cached)
            return
        }

        let expected = urlString
        Task {
            if let disk = await ImageCache.loadFromDisk(urlString: urlString) {
                guard loadedURL == expected else { return }
                applyColor(from: disk)
            } else if let url = URL(string: urlString),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = NSImage(data: data) {
                guard loadedURL == expected else { return }
                ImageCache.saveToMemory(image, urlString: urlString)
                applyColor(from: image)
            }
        }
    }

    private func applyColor(from image: NSImage) {
        let c = image.averageColor()
        withAnimation(.easeOut(duration: 0.5)) { color = c }
    }
}

// MARK: - Helpers

func formatCacheSize(_ bytes: Int64) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    let kb = Double(bytes) / 1024
    if kb < 1024 { return String(format: "%.1f KB", kb) }
    let mb = kb / 1024
    return String(format: "%.1f MB", mb)
}
