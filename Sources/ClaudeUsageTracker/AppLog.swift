import Foundation

/// Appends timestamped diagnostics to ~/Library/Logs/ClaudeUsageTracker.log.
/// NSLog from this app does not reliably reach the unified log, and the app has
/// no console when launched normally, so a plain file is the debugging surface.
enum AppLog {
    private static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ClaudeUsageTracker.log")

    private static let queue = DispatchQueue(label: "applog")

    static func log(_ message: String) {
        queue.async {
            let formatter = ISO8601DateFormatter()
            let line = "\(formatter.string(from: Date())) \(message)\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
