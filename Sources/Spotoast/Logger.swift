import Foundation

final class AppLogger {
    static let shared = AppLogger()
    private let queue = DispatchQueue(label: "com.toast1.spotoast.logger")
    private let maxSize = 512 * 1024 // 512KB

    var logURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spotoast", isDirectory: true)
            .appendingPathComponent("spotoast.log")
    }

    private init() {
        let dir = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func log(_ message: String, level: String = "INFO") {
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"

        queue.async { [self] in
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
                fh2.write(line.data(using: .utf8)!)
                fh2.closeFile()
            } else {
                fh.write(line.data(using: .utf8)!)
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
        guard let data = try? Data(contentsOf: logURL),
              let content = String(data: data, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n")
        let keep = lines.suffix(lines.count / 2).joined(separator: "\n")
        try? keep.data(using: .utf8)?.write(to: logURL)
    }
}

let logger = AppLogger.shared
