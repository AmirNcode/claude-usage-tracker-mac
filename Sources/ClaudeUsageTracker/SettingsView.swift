import SwiftUI
import UsageCore

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var state: AppState
    let auth: AuthManager
    var onRefreshNow: () -> Void
    var onPrefsChanged: () -> Void

    private let repoURL = URL(string: "https://github.com/AmirNcode/claude-usage-tracker-mac")!
    private let issuesURL = URL(string: "https://github.com/AmirNcode/claude-usage-tracker-mac/issues")!

    var body: some View {
        TabView {
            accountTab.tabItem { Label("Account", systemImage: "person.crop.circle") }
            appearanceTab.tabItem { Label("Appearance", systemImage: "paintpalette") }
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 360)
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
                Text("Turns a percentage orange at \(Int(UsageLevel.warningThreshold))% and red at \(Int(UsageLevel.criticalThreshold))%, overriding the colors below.")
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
