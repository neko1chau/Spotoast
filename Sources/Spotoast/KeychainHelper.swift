import Foundation
import CryptoKit

enum KeychainHelper {
    private static var storageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let appDir = dir.appendingPathComponent("Spotoast", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("tokens.enc")
    }

    private static var encryptionKey: SymmetricKey {
        let seed = hardwareUUID() ?? "com.toast1.spotoast.fallback-key"
        let hash = SHA256.hash(data: Data(seed.utf8))
        return SymmetricKey(data: hash)
    }

    static func save(key: String, value: String) {
        var dict = readAll()
        dict[key] = value
        writeAll(dict)
    }

    static func read(key: String) -> String? {
        readAll()[key]
    }

    static func delete(key: String) {
        var dict = readAll()
        dict.removeValue(forKey: key)
        writeAll(dict)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: storageURL)
    }

    static func migrateIfNeeded() {
        // Migrate from old plaintext JSON
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let oldFile = dir.appendingPathComponent("spotoast_tokens.json")
        if FileManager.default.fileExists(atPath: oldFile.path),
           let data = try? Data(contentsOf: oldFile),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            writeAll(dict)
            try? FileManager.default.removeItem(at: oldFile)
        }
        // Only migrate from Keychain if we have no encrypted tokens yet
        if readAll().isEmpty {
            migrateFromKeychain()
        }
    }

    // MARK: - Private

    private static func readAll() -> [String: String] {
        guard let encrypted = try? Data(contentsOf: storageURL) else { return [:] }
        guard let box = try? ChaChaPoly.SealedBox(combined: encrypted),
              let plaintext = try? ChaChaPoly.open(box, using: encryptionKey),
              let dict = try? JSONDecoder().decode([String: String].self, from: plaintext)
        else { return [:] }
        return dict
    }

    private static func writeAll(_ dict: [String: String]) {
        guard let json = try? JSONEncoder().encode(dict),
              let box = try? ChaChaPoly.seal(json, using: encryptionKey) else { return }
        try? box.combined.write(to: storageURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
    }

    private static func hardwareUUID() -> String? {
        let service = IOServiceMatching("IOPlatformExpertDevice")
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, service, &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        let entry = IOIteratorNext(iter)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        let key = "IOPlatformUUID" as CFString
        guard let uuid = IORegistryEntryCreateCFProperty(entry, key, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String else { return nil }
        return uuid
    }

    private static func migrateFromKeychain() {
        let keys = ["client_id", "access_token", "refresh_token"]
        var migrated: [String: String] = [:]
        for key in keys {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.toast1.spotoast",
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data,
               let str = String(data: data, encoding: .utf8) {
                migrated[key] = str
            }
        }
        guard !migrated.isEmpty else { return }
        var existing = readAll()
        for (k, v) in migrated where existing[k] == nil {
            existing[k] = v
        }
        writeAll(existing)
        // Clean up Keychain entries
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.toast1.spotoast"
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }
}
