import SwiftUI
import UsageCore

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var state: AppState
    @ObservedObject var history: UsageHistoryStore
    let auth: AuthManager
    var onRefreshNow: () -> Void
    var onPrefsChanged: () -> Void

    private let repoURL = URL(string: "https://github.com/AmirNcode/claude-usage-tracker-mac")!
    private let issuesURL = URL(string: "https://github.com/AmirNcode/claude-usage-tracker-mac/issues")!

    enum Pane: String, CaseIterable, Identifiable {
        case account = "Account"
        case appearance = "Appearance"
        case general = "General"
        case data = "Data"
        case about = "About"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .account: return "person.crop.circle"
            case .appearance: return "paintpalette"
            case .general: return "gearshape"
            case .data: return "chart.xyaxis.line"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selection: Pane? = .account

    var body: some View {
        // Permanent left panel + detail. No collapse control: the sidebar is
        // always shown.
        HStack(spacing: 0) {
            List(Pane.allCases, selection: $selection) { pane in
                Label(pane.rawValue, systemImage: pane.icon).tag(pane)
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 620, height: 400)
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .account {
        case .account: accountTab
        case .appearance: appearanceTab
        case .general: generalTab
        case .data: dataTab
        case .about: aboutTab
        }
    }

    // MARK: - Account

    @State private var pastedCode = ""
    @State private var loginInProgress = false
    @State private var loginError: String?

    private var accountTab: some View {
        Form {
            Section {
                LabeledContent("Status", value: state.connectionDescription)
                LabeledContent("Last refreshed", value: state.lastRefreshedDescription)
                if let err = state.lastError {
                    LabeledContent("Last error") { Text(err).foregroundStyle(.secondary) }
                }
            }

            Section("Connection") {
                if auth.isLoggedInViaOAuth {
                    Text("You're logged in with your Claude account.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Log out") {
                        auth.logout()
                        refreshSourceAndData()
                    }
                } else {
                    Text("Log in to read usage from your own Claude account. Without logging in, the app uses Claude Code's session if it's installed.")
                        .font(.callout).foregroundStyle(.secondary)
                    if loginInProgress {
                        Text("A browser window opened. Approve access, copy the code shown, paste it below, and click Connect.")
                            .font(.callout)
                        TextField("Paste authorization code", text: $pastedCode)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Connect") { connect() }
                                .keyboardShortcut(.defaultAction)
                                .disabled(pastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
                            Button("Cancel") { loginInProgress = false; pastedCode = "" }
                        }
                    } else {
                        Button("Log in with Claude…") {
                            loginError = nil
                            auth.beginLogin()
                            loginInProgress = true
                        }
                    }
                    if let loginError {
                        Text(loginError).font(.callout).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func connect() {
        let code = pastedCode
        Task {
            do {
                try await auth.completeLogin(pastedCode: code)
                await MainActor.run {
                    loginInProgress = false
                    pastedCode = ""
                    loginError = nil
                    refreshSourceAndData()
                }
            } catch {
                await MainActor.run { loginError = "\(error)" }
            }
        }
    }

    private func refreshSourceAndData() {
        state.source = auth.source
        onRefreshNow()
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section("Threshold colors") {
                Toggle("Highlight high usage", isOn: $prefs.thresholdsEnabled)
                Text("At \(Int(UsageLevel.warningThreshold))% the session ring and % turn orange and the weekly ones yellow; both turn red at \(Int(UsageLevel.criticalThreshold))%. Overrides the colors below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar colors") {
                ColorRow(title: "Session %", hex: $prefs.sessionColorHex)
                ColorRow(title: "Weekly %", hex: $prefs.weeklyColorHex)
                Text("Leave as Automatic to match the menu bar's normal text color.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: prefs.thresholdsEnabled) { onPrefsChanged() }
        .onChange(of: prefs.sessionColorHex) { onPrefsChanged() }
        .onChange(of: prefs.weeklyColorHex) { onPrefsChanged() }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
                Picker("Refresh every", selection: $prefs.refreshMinutes) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                }
                Text("Usage windows change slowly; 5 minutes is plenty and avoids rate limits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Refresh now") { onRefreshNow() }
            }
        }
        .formStyle(.grouped)
        .onChange(of: prefs.launchAtLogin) { onPrefsChanged() }
        .onChange(of: prefs.refreshMinutes) { onPrefsChanged() }
    }

    // MARK: - Data

    @State private var manualDate = Date()
    @State private var manualSession = ""
    @State private var manualWeekly = ""
    @State private var manualStatus: String?
    @State private var manualStatusIsError = false
    @State private var confirmReset = false

    private var dataTab: some View {
        Form {
            Section("Manual entry") {
                Text("Record a reading the app missed — a session reset it slept through, or a stretch where it couldn't authenticate. Pick the time it happened; the chart redraws around it.")
                    .font(.callout).foregroundStyle(.secondary)
                DatePicker("Time", selection: $manualDate,
                           in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                TextField("Session %", text: $manualSession)
                TextField("Weekly %", text: $manualWeekly)
                HStack {
                    Button("Add to history") { addManualSample() }
                        .disabled(manualSession.isEmpty && manualWeekly.isEmpty)
                    if let manualStatus {
                        Text(manualStatus).font(.caption)
                            .foregroundStyle(manualStatusIsError ? Color.red : .secondary)
                    }
                }
                Text("Leave a field blank to leave that series unset at this point. History only — the menu bar keeps showing live values.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Reset") {
                Button("Reset charts…", role: .destructive) { confirmReset = true }
                Text("Erases the \(history.samples.count) stored readings and starts over from the current one. Use it when a sync gap has left the chart drawing a line across data it never collected.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Text("History lives in ~/Library/Application Support/ClaudeUsageTracker/history.json and is pruned to the last 14 days.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Reset usage charts?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { resetCharts() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes all \(history.samples.count) recorded readings. It can't be undone.")
        }
    }

    private func resetCharts() {
        history.reset(seeding: state.snapshot)
        manualStatus = nil
        onRefreshNow()
    }

    private func addManualSample() {
        guard let session = Self.percentage(manualSession),
              let weekly = Self.percentage(manualWeekly) else {
            manualStatus = "Enter percentages between 0 and 100."
            manualStatusIsError = true
            return
        }
        history.addManual(session: session, weekly: weekly, at: manualDate)
        manualSession = ""
        manualWeekly = ""
        manualStatusIsError = false
        manualStatus = "Added."
    }

    /// Parses a percentage field: blank is a valid "unset" (.some(nil)); anything
    /// outside 0–100 or unparseable is rejected (nil).
    private static func percentage(_ text: String) -> Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "%", with: "")
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), (0...100).contains(value) else { return nil }
        return .some(value)
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
            Text("Claude Usage Tracker").font(.headline)
            Text("Version \(Bundle.main.shortVersion)")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Shows your Claude session and weekly usage in the menu bar.")
                .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("GitHub", destination: repoURL)
                Link("Report an issue", destination: issuesURL)
            }
            .font(.callout)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A color well with an "Automatic" reset, bound to a hex string ("" = automatic).
private struct ColorRow: View {
    let title: String
    @Binding var hex: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if !hex.isEmpty {
                Button("Automatic") { hex = "" }
                    .buttonStyle(.borderless).font(.caption)
            }
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: NSColor(hex: hex) ?? .labelColor) },
                set: { hex = NSColor($0).hexString }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}
