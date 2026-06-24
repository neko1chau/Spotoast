import Foundation

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()
    private let queue = DispatchQueue(label: "com.toast1.spotoast.logger")
    private let maxSize = 512 * 1024

    var logURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return dir.appendingPathComponent("Spotoast", isDirectory: true)
            .appendingPathComponent("spotoast.log")
    }

    private init() {
        let dir = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func log(_ message: String, level: String = "INFO") {
        queue.async { [self] in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
            let timestamp = formatter.string(from: Date())
            guard let lineData = "[\(timestamp)] [\(level)] \(message)\n".data(using: .utf8) else { return }

            let fm = FileManager.default
            let path = logURL.path
            if !fm.fileExists(atPath: path) {
                fm.createFile(atPath: path, contents: nil)
            }
            guard let fh = FileHandle(forWritingAtPath: path) else { return }
            let size = fh.seekToEndOfFile()
            if size > UInt64(maxSize) {
                fh.closeFile()
                truncateLog()
                guard let fh2 = FileHandle(forWritingAtPath: path) else { return }
                fh2.seekToEndOfFile()
                fh2.write(lineData)
                fh2.closeFile()
            } else {
                fh.write(lineData)
                fh.closeFile()
            }
        }
    }

    func info(_ msg: String) { log(msg, level: "INFO") }
    func error(_ msg: String) { log(msg, level: "ERROR") }
    func warn(_ msg: String) { log(msg, level: "WARN") }

    func readLog() -> String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? "(empty)"
    }

    func clearLog() {
        try? FileManager.default.removeItem(at: logURL)
    }

    func logSize() -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int) ?? 0
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return "\(size / 1024) KB" }
        return String(format: "%.1f MB", Double(size) / 1048576)
    }

    private func truncateLog() {
        guard let data = try? Data(contentsOf: logURL) else { return }
        let keepBytes = maxSize / 2
        if data.count > keepBytes {
            let trimmed = data.suffix(keepBytes)
            if let str = String(data: trimmed, encoding: .utf8),
               let firstNewline = str.firstIndex(of: "\n") {
                let clean = String(str[str.index(after: firstNewline)...])
                try? clean.data(using: .utf8)?.write(to: logURL, options: .atomic)
            }
        }
    }
}

let logger = AppLogger.shared
