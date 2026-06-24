import Foundation

enum KeychainHelper {
    private static let lock = NSLock()

    private static var storageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("spotoast_tokens.json")
    }

    static func save(key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        var dict = readAllUnsafe() ?? [:]
        dict[key] = value
        writeAllUnsafe(dict)
    }

    static func read(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return readAllUnsafe()?[key]
    }

    static func delete(key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var dict = readAllUnsafe() else { return }
        dict.removeValue(forKey: key)
        writeAllUnsafe(dict)
    }

    static func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: storageURL)
    }

    private static func readAllUnsafe() -> [String: String]? {
        guard let data = try? Data(contentsOf: storageURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        return dict
    }

    private static func writeAllUnsafe(_ dict: [String: String]) {
        let url = storageURL
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
