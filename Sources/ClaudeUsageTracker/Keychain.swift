import Foundation

/// Thin wrapper over the `security` CLI for generic-password items.
///
/// Using the CLI (rather than SecItem) keeps access working across ad-hoc rebuilds
/// of an unsigned app, whose code-signing identity changes each build and would
/// otherwise trigger Keychain ACL prompts. Items are stored with `-A` (accessible
/// without per-app prompts) — acceptable for a single-user local utility.
enum Keychain {
    /// Reads a generic-password item's data, or nil if absent.
    static func read(service: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        // `-w` prints the raw password followed by a newline.
        var bytes = data
        if bytes.last == 0x0A { bytes.removeLast() }
        return bytes
    }

    @discardableResult
    static func write(service: String, account: String, data: Data) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "add-generic-password",
            "-U", // update if it exists
            "-A", // no per-app access prompts
            "-s", service,
            "-a", account,
            "-w", String(data: data, encoding: .utf8) ?? "",
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    @discardableResult
    static func delete(service: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["delete-generic-password", "-s", service]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
