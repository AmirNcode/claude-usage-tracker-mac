import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UsageCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let prefs = Preferences.shared
    private let state = AppState()
    private let auth = AuthManager()
    private let client = UsageClient()
    private let history = UsageHistoryStore()

    private var statusItem: NSStatusItem!
    private let statusView = StatusBarView()
    private var sessionItem: NSMenuItem!
    private var weeklyItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private var statsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    // While the Stats window is open, sample more often so prompt-driven jumps show.
    private let statsOpenInterval: TimeInterval = 60
    private var statsWindowOpen = false

    // Variable-interval polling with exponential backoff on failure.
    private var pollWorkItem: DispatchWorkItem?
    private var consecutiveFailures = 0
    private let maxBackoff: TimeInterval = 30 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: statusView.preferredWidth)
        statusItem.menu = buildMenu()
        if let button = statusItem.button {
            statusView.frame = button.bounds
            statusView.autoresizingMask = [.width, .height]
            button.addSubview(statusView)
            button.setAccessibilityLabel("Claude usage")
        }
        render()

        state.source = auth.source
        applyLaunchAtLogin(prefs.launchAtLogin)

        // Re-render the menu bar and re-apply login item whenever settings change.
        prefs.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.render()
                    self.applyLaunchAtLogin(self.prefs.launchAtLogin)
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        refresh()

        // Dev affordance for verification: `--open-stats` shows the Stats window
        // immediately (no menu interaction needed).
        if CommandLine.arguments.contains("--open-stats") {
            DispatchQueue.main.async { [weak self] in
                self?.openStats()
                self?.statsWindow?.level = .floating // float above other apps for capture
            }
        }
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.async { [weak self] in
                self?.openSettings()
                self?.settingsWindow?.level = .floating
            }
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        sessionItem = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        weeklyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        sessionItem.isEnabled = false
        weeklyItem.isEnabled = false
        menu.addItem(sessionItem)
        menu.addItem(weeklyItem)
        menu.addItem(.separator())

        add(menu, "Stats…", #selector(openStats), key: "s")
        add(menu, "Refresh Now", #selector(refreshNow), key: "r")
        add(menu, "Settings…", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        add(menu, "Quit Claude Usage Tracker", #selector(NSApplication.terminate(_:)), key: "q")
        return menu
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    // MARK: - Rendering

    private func render() {
        renderStatusItem(state.snapshot)
        if let snapshot = state.snapshot {
            sessionItem.title = "Session   " + UsageFormatter.sessionLine(snapshot)
            weeklyItem.title  = "Weekly    " + UsageFormatter.weeklyLine(snapshot)
        } else {
            sessionItem.title = statusLineWhenNoData()
            weeklyItem.title = ""
        }
    }

    private func statusLineWhenNoData() -> String {
        switch auth.source {
        case .none: return "Not connected — open Settings to log in"
        default: return state.lastError ?? "Loading…"
        }
    }

    /// Updates the ring/pie icon and stacked percentages in the menu bar.
    private func renderStatusItem(_ snapshot: UsageSnapshot?) {
        let session = snapshot?.session?.utilization
        let weekly = snapshot?.weekly?.utilization
        let sessionLevel = UsageLevel(utilization: session, thresholdsEnabled: prefs.thresholdsEnabled)
        let weeklyLevel = UsageLevel(utilization: weekly, thresholdsEnabled: prefs.thresholdsEnabled)
        let hasData = snapshot != nil
        statusView.content = StatusBarView.Content(
            session: hasData ? (session ?? 0) : nil,
            weekly: hasData ? (weekly ?? 0) : nil,
            sessionRingColor: AppColors.ringColor(level: sessionLevel, warning: AppColors.sessionWarning),
            weeklyRingColor: AppColors.ringColor(level: weeklyLevel, warning: AppColors.weeklyWarning),
            sessionTextColor: AppColors.color(level: sessionLevel, warning: AppColors.sessionWarning,
                                              customHex: prefs.sessionColorHex),
            weeklyTextColor: AppColors.color(level: weeklyLevel, warning: AppColors.weeklyWarning,
                                             customHex: prefs.weeklyColorHex)
        )
        statusItem.button?.toolTip = hasData ? UsageFormatter.menuBarTitle(snapshot) : nil
    }

    /// Refresh the cached source/line text when the menu is about to show.
    func menuWillOpen(_ menu: NSMenu) {
        state.source = auth.source
        if state.snapshot == nil { render() }
    }

    // MARK: - Polling

    @objc private func refreshNow() { refresh() }

    @objc private func didWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.refresh() }
    }

    private func refresh() {
        state.isRefreshing = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await self.tokenWithRetry()
                let snapshot = try await self.client.fetchUsage(accessToken: token)
                await MainActor.run { self.onSuccess(snapshot) }
            } catch {
                await MainActor.run { self.onFailure(error) }
            }
        }
    }

    /// Fetch a token, and on a 401 force a refresh/re-read once before giving up.
    private func tokenWithRetry() async throws -> String {
        let token = try await auth.accessToken()
        return token
    }

    private func onSuccess(_ snapshot: UsageSnapshot) {
        state.snapshot = snapshot
        state.lastRefreshed = Date()
        state.lastError = nil
        state.isRefreshing = false
        state.source = auth.source
        history.record(snapshot)
        consecutiveFailures = 0
        render()
        scheduleNextPoll(after: normalInterval())
    }

    /// Poll faster while the Stats window is open (short bursts only).
    private func normalInterval() -> TimeInterval {
        statsWindowOpen ? min(statsOpenInterval, prefs.refreshInterval) : prefs.refreshInterval
    }

    private func onFailure(_ error: Error) {
        AppLog.log("Usage refresh failed: \(error)")
        state.isRefreshing = false
        state.source = auth.source
        consecutiveFailures += 1

        // On an auth failure, try once more after forcing a token refresh/re-read.
        if case UsageClientError.unauthorized = error, consecutiveFailures == 1 {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let token = try await self.auth.accessToken(forceRefresh: true)
                    let snapshot = try await self.client.fetchUsage(accessToken: token)
                    await MainActor.run { self.onSuccess(snapshot) }
                } catch {
                    await MainActor.run { self.finishFailure(error) }
                }
            }
            return
        }
        finishFailure(error)
    }

    private func finishFailure(_ error: Error) {
        state.lastError = friendlyError(error)
        render()

        var delay = max(backoffDelay(), normalInterval())
        if case UsageClientError.rateLimited(let retryAfter) = error, let retryAfter {
            delay = max(delay, retryAfter)
        }
        scheduleNextPoll(after: delay)
    }

    private func backoffDelay() -> TimeInterval {
        let base = prefs.refreshInterval
        let scaled = base * pow(2, Double(min(consecutiveFailures, 6)))
        return min(scaled, maxBackoff)
    }

    private func friendlyError(_ error: Error) -> String {
        switch error {
        case AuthError.notLoggedIn: return "Not connected — log in via Settings"
        case UsageClientError.unauthorized: return "Token expired — log in again or use Claude Code"
        case UsageClientError.rateLimited: return "Rate limited — backing off"
        default: return "\(error)"
        }
    }

    private func scheduleNextPoll(after delay: TimeInterval) {
        pollWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pollWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Settings window

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                prefs: prefs, state: state, history: history, auth: auth,
                onRefreshNow: { [weak self] in self?.refresh() },
                onPrefsChanged: { [weak self] in
                    self?.render()
                    self?.applyLaunchAtLogin(self?.prefs.launchAtLogin ?? true)
                }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 400),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            window.title = "Claude Usage Tracker"
            window.contentViewController = NSHostingController(rootView: view)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openStats() {
        if statsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
            )
            window.title = "Usage Stats"
            window.contentViewController = NSHostingController(rootView: StatsView(store: history))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            statsWindow = window
        }
        statsWindowOpen = true
        NSApp.activate(ignoringOtherApps: true)
        statsWindow?.makeKeyAndOrderFront(nil)
        refresh() // immediate sample, then faster cadence while open
    }

    // NSWindowDelegate: return to the normal poll cadence when Stats closes.
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) == statsWindow {
            statsWindowOpen = false
            scheduleNextPoll(after: prefs.refreshInterval)
        }
    }

    // MARK: - Launch at login

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let service = SMAppService.mainApp
        do {
            let isEnabled = service.status == .enabled
            if enabled && !isEnabled {
                try service.register()
            } else if !enabled && isEnabled {
                try service.unregister()
            }
        } catch {
            AppLog.log("Launch at login update failed: \(error)")
        }
    }
}
