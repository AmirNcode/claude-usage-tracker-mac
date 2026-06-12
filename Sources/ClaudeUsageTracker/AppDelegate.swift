import AppKit
import ServiceManagement
import UsageCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let refreshInterval: TimeInterval = 60

    private let client = UsageClient()
    private let notifications = NotificationManager()
    private let defaults = UserDefaults.standard

    private var statusItem: NSStatusItem!
    private var sessionItem: NSMenuItem!
    private var weeklyItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var notificationsItem: NSMenuItem!
    private var timer: Timer?
    private var lastSnapshot: UsageSnapshot?

    private var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private var notificationsEnabled: Bool {
        get { defaults.object(forKey: "notificationsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notificationsEnabled") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        statusItem.button?.title = UsageFormatter.menuBarTitle(nil)
        statusItem.menu = buildMenu()

        notifications.requestAuthorization()
        registerLaunchAtLoginOnFirstRun()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = 5
        refresh()
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        sessionItem = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
        weeklyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(sessionItem)
        menu.addItem(weeklyItem)

        let settingsMenu = NSMenu()
        settingsMenu.autoenablesItems = false

        launchAtLoginItem = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        settingsMenu.addItem(launchAtLoginItem)

        notificationsItem = NSMenuItem(
            title: "Notifications", action: #selector(toggleNotifications), keyEquivalent: ""
        )
        notificationsItem.target = self
        settingsMenu.addItem(notificationsItem)

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        settingsMenu.addItem(refreshItem)

        settingsMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        settingsMenu.addItem(quitItem)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        menu.addItem(settingsItem)
        menu.setSubmenu(settingsMenu, for: settingsItem)

        return menu
    }

    /// Keep checkmarks current; login item status can change in System Settings.
    func menuWillOpen(_ menu: NSMenu) {
        notificationsItem.state = notificationsEnabled ? .on : .off
        if isRunningFromAppBundle {
            launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchAtLoginItem.isEnabled = false
        }
    }

    // MARK: - Refresh

    @objc private func refreshNow() { refresh() }

    @objc private func didWake() {
        // Give the network a moment to come back up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await self.client.fetchUsage()
                await MainActor.run { self.apply(snapshot) }
            } catch {
                await MainActor.run { self.applyError(error) }
            }
        }
    }

    private func apply(_ snapshot: UsageSnapshot) {
        lastSnapshot = snapshot
        statusItem.button?.title = UsageFormatter.menuBarTitle(snapshot)
        sessionItem.title = UsageFormatter.sessionLine(snapshot)
        weeklyItem.title = UsageFormatter.weeklyLine(snapshot)
        notifications.process(snapshot: snapshot, notificationsEnabled: notificationsEnabled)
    }

    private func applyError(_ error: Error) {
        AppLog.log("Usage refresh failed: \(error)")
        // Keep showing the last known data; only surface errors when there is none.
        guard lastSnapshot == nil else { return }
        statusItem.button?.title = UsageFormatter.menuBarTitle(nil)
        switch error {
        case UsageClientError.keychainItemNotFound, UsageClientError.malformedCredentials:
            sessionItem.title = "Claude Code not logged in"
        case UsageClientError.unauthorized:
            sessionItem.title = "Token expired — use Claude Code"
        default:
            sessionItem.title = "Offline — retrying every minute"
        }
        weeklyItem.title = ""
    }

    // MARK: - Settings actions

    @objc private func toggleNotifications() {
        notificationsEnabled.toggle()
        // Re-run the decider so pending notifications are scheduled or cancelled.
        if let lastSnapshot {
            notifications.process(snapshot: lastSnapshot, notificationsEnabled: notificationsEnabled)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        guard isRunningFromAppBundle else { return }
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            AppLog.log("Launch at login toggle failed: \(error)")
        }
    }

    /// User chose auto-start at login; register once on first launch from /Applications.
    private func registerLaunchAtLoginOnFirstRun() {
        guard isRunningFromAppBundle,
              Bundle.main.bundlePath.hasPrefix("/Applications/"),
              !defaults.bool(forKey: "didRegisterLoginItem")
        else { return }
        do {
            try SMAppService.mainApp.register()
            defaults.set(true, forKey: "didRegisterLoginItem")
        } catch {
            AppLog.log("Initial launch-at-login registration failed: \(error)")
        }
    }
}
