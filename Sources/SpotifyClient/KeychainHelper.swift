import Foundation

/// Simple file‑based token store.
///
/// SPM‑built macOS executables are not code‑signed, so Keychain access
/// (`SecItemAdd` / `SecItemCopyMatching`) is unreliable and may require
/// multiple build attempts.  A JSON file in the user's Application Support
/// directory avoids these entitlement issues entirely.
enum KeychainHelper {
    private static var storageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("spotoast_tokens.json")
    }

    static func save(key: String, value: String) {
        var dict = readAll() ?? [:]
        dict[key] = value
        writeAll(dict)
    }

    static func read(key: String) -> String? {
        readAll()?[key]
    }

    static func delete(key: String) {
        guard var dict = readAll() else { return }
        dict.removeValue(forKey: key)
        writeAll(dict)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: storageURL)
    }

    private static func readAll() -> [String: String]? {
        guard let data = try? Data(contentsOf: storageURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        return dict
    }

    private static func writeAll(_ dict: [String: String]) {
        let url = storageURL
        try? JSONEncoder().encode(dict).write(to: url)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
