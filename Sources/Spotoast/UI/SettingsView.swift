import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var updateManager = UpdateManager()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.auto
    @AppStorage("simpleMode") private var simpleMode = false
    @AppStorage("cacheLyrics") private var cacheLyrics = false
    @AppStorage("cacheCovers") private var cacheCovers = false
    @State private var editingClientId = false
    @State private var clientIdInput = ""
    @State private var cacheSize: String?
    @State private var showClearConfirm = false
    @State private var showLogoutConfirm = false
    @State private var showLogViewer = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .onChange(of: appearanceMode) { mode in mode.apply() }

                Toggle("Simple sidebar", isOn: $simpleMode)
                    .help("Show Liked Songs directly in the sidebar instead of Library and Playlists")
                Text("Show Liked Songs directly in the sidebar instead of Library and Playlists.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Cache") {
                Toggle("Lyrics", isOn: $cacheLyrics)
                Toggle("Album covers", isOn: $cacheCovers)
                HStack {
                    Text(cacheSize ?? "0 B")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") { showClearConfirm = true }
                        .alert("Clear all cached data?", isPresented: $showClearConfirm) {
                            Button("Clear", role: .destructive) {
                                Task {
                                    await LyricsCache.disk.clear()
                                    await ImageCache.disk.clear()
                                    await updateCacheSize()
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                }
            }

            Section("Updates") {
                Toggle("Check automatically", isOn: $updateManager.checkForUpdates)
                HStack {
                    if updateManager.isChecking {
                        Text("Checking...").foregroundColor(.secondary)
                    } else if updateManager.hasUpdate, let version = updateManager.latestVersion {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("v\(version) available").fontWeight(.medium)
                        Spacer()
                        if updateManager.isDownloading {
                            Text("Downloading...").foregroundColor(.secondary)
                        } else {
                            Button("Update") {
                                Task { await updateManager.downloadAndInstall() }
                            }
                        }
                    } else if updateManager.latestVersion != nil {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Up to date").foregroundColor(.secondary)
                        Spacer()
                    } else {
                        Spacer()
                    }
                    if !updateManager.isChecking && !updateManager.hasUpdate {
                        Spacer()
                        Button("Check Now") {
                            Task { await updateManager.checkForUpdate() }
                        }
                        .disabled(updateManager.isChecking)
                    }
                }
                if let error = updateManager.error {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }

            Section("Logs") {
                HStack {
                    Text(logger.logSize()).foregroundColor(.secondary)
                    Spacer()
                    Button("Export") {
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "spotoast.log"
                        panel.allowedContentTypes = [.plainText]
                        if panel.runModal() == .OK, let url = panel.url {
                            try? FileManager.default.copyItem(at: logger.logURL, to: url)
                        }
                    }
                    Button("View") { showLogViewer = true }
                    Button("Clear") { logger.clearLog() }
                }
            }

            Section("Account") {
                if editingClientId {
                    HStack {
                        TextField("Client ID", text: $clientIdInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            authManager.saveClientId(clientIdInput)
                            editingClientId = false
                        }
                        .disabled(clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Cancel") {
                            clientIdInput = authManager.clientId
                            editingClientId = false
                        }
                    }
                } else {
                    HStack {
                        Text(authManager.clientId.prefix(12) + "••••")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Edit") { editingClientId = true }
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                    Text("Credentials stored locally only")
                }
                .foregroundColor(.secondary)
                .font(.caption)

                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Text("Logout")
                }
                .confirmationDialog("Log out of Spotify?", isPresented: $showLogoutConfirm) {
                    Button("Logout", role: .destructive) { authManager.logout() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You will need to re-authenticate with Spotify.")
                }
            }

            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Spotoast v\(UpdateManager.currentVersion)")
                            .foregroundColor(.secondary)
                        Link("GitHub", destination: URL(string: "https://github.com/neko1chau/Spotoast")!)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showLogViewer) { LogViewerSheet() }
        .onAppear {
            clientIdInput = authManager.clientId
            if updateManager.checkForUpdates {
                Task { await updateManager.checkForUpdate() }
            }
            Task { await updateCacheSize() }
        }
    }

    private func updateCacheSize() async {
        let lyrics = await LyricsCache.disk.sizeBytes
        let images = await ImageCache.disk.sizeBytes
        cacheSize = formatCacheSize(lyrics + images)
    }
}

private func formatCacheSize(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
    return String(format: "%.1f MB", Double(bytes) / 1048576)
}

private struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Application Log").font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                }
                .controlSize(.small)
                Button("Close") { dismiss() }
                    .controlSize(.small)
            }
            .padding()

            ScrollView {
                Text(logText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .textSelection(.enabled)
            }
        }
        .frame(width: 600, height: 400)
        .onAppear { logText = logger.readLog() }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    func apply() {
        switch self {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
