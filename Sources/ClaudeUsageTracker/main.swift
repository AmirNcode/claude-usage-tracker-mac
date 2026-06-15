import AppKit
import UsageCore

// Headless mode for verification/debugging: prints what the menu bar would show.
if CommandLine.arguments.contains("--status") {
    let auth = AuthManager()
    let client = UsageClient()
    Task {
        do {
            let token = try await auth.accessToken()
            let snapshot = try await client.fetchUsage(accessToken: token)
            print("source:  \(auth.source)")
            print("title:   \(UsageFormatter.menuBarTitle(snapshot))")
            print("session: \(UsageFormatter.sessionLine(snapshot))")
            print("weekly:  \(UsageFormatter.weeklyLine(snapshot))")
            exit(0)
        } catch {
            print("error: \(error)")
            exit(1)
        }
    }
    dispatchMain()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
