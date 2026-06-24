import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var updateManager = UpdateManager()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.auto
    @AppStorage("cacheLyrics") private var cacheLyrics = false
    @AppStorage("cacheCovers") private var cacheCovers = false
    var onLogout: (() -> Void)?
    @State private var editingClientId = false
    @State private var clientIdInput = ""
    @State private var cacheSize: String?
    @State private var showClearConfirm = false
    @State private var showLogViewer = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                aboutHeader
                    .padding(.bottom, 20)

                VStack(spacing: 0) {
                    card(isTop: true) { appearanceContent }
                    Divider().padding(.horizontal, 16)
                    card { cacheContent }
                    Divider().padding(.horizontal, 16)
                    card { updateContent }
                    Divider().padding(.horizontal, 16)
                    card { logContent }
                    Divider().padding(.horizontal, 16)
                    card(isBottom: true) { accountContent }
                }
                .glassCard(cornerRadius: 10)

                Spacer().frame(height: 20)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            clientIdInput = authManager.clientId
            if updateManager.checkForUpdates {
                Task { await updateManager.checkForUpdate() }
            }
            Task { await updateCacheSize() }
        }
    }

    // MARK: - Card wrapper

    private func card<Content: View>(isTop: Bool = false, isBottom: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - About

    private var aboutHeader: some View {
        VStack(spacing: 6) {
            if let iconURL = Bundle.module.url(forResource: "Spotoast", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }

            Text("Spotoast")
                .font(.system(size: 18, weight: .semibold))

            HStack(spacing: 8) {
                Text("v\(UpdateManager.currentVersion)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Link(destination: URL(string: "https://github.com/neko1chau/Spotoast")!) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9))
                        Text("GitHub")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Appearance

    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingLabel("Appearance")

            Picker("", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: appearanceMode) { mode in
                mode.apply()
            }
        }
    }

    // MARK: - Cache

    private var cacheContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingLabel("Cache")

            settingRow("Lyrics") {
                Toggle("", isOn: $cacheLyrics)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            settingRow("Album covers") {
                Toggle("", isOn: $cacheCovers)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            HStack(spacing: 6) {
                Text(cacheSize ?? "0 B")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear") { showClearConfirm = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
            .padding(.top, 2)
        }
    }

    private func updateCacheSize() async {
        let lyrics = await LyricsCache.disk.sizeBytes
        let images = await ImageCache.disk.sizeBytes
        cacheSize = formatCacheSize(lyrics + images)
    }

    // MARK: - Updates

    private var updateContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingLabel("Updates")

            settingRow("Check automatically") {
                Toggle("", isOn: $updateManager.checkForUpdates)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            HStack(spacing: 6) {
                if updateManager.isChecking {
                    Text("Checking...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else if updateManager.hasUpdate, let version = updateManager.latestVersion {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text("v\(version) available")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    if updateManager.isDownloading {
                        Text("Downloading...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Button("Update") {
                            Task { await updateManager.downloadAndInstall() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                    }
                } else if updateManager.latestVersion != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                    Text("Up to date")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Spacer()
                }

                if !updateManager.isChecking && !updateManager.hasUpdate {
                    Spacer()
                    Button("Check Now") {
                        Task { await updateManager.checkForUpdate() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(updateManager.isChecking)
                }
            }

            if let error = updateManager.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Account

    private var accountContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingLabel("Account")

            if editingClientId {
                HStack(spacing: 6) {
                    TextField("Client ID", text: $clientIdInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    Button("Save") {
                        authManager.saveClientId(clientIdInput)
                        editingClientId = false
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") {
                        clientIdInput = authManager.clientId
                        editingClientId = false
                    }
                    .controlSize(.small)
                }
            } else {
                settingRow(authManager.clientId.prefix(12) + "••••") {
                    Button("Edit") { editingClientId = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                Text("Credentials stored locally only")
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary.opacity(0.6))

            Divider().padding(.vertical, 2)

            Button(role: .destructive) {
                onLogout?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 10))
                    Text("Logout")
                        .font(.system(size: 11))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.red.opacity(0.8))
        }
    }

    // MARK: - Logs

    private var logContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingLabel("Logs")

            HStack(spacing: 6) {
                Text(logger.logSize())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Export") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "spotoast.log"
                    panel.allowedContentTypes = [.plainText]
                    if panel.runModal() == .OK, let url = panel.url {
                        try? FileManager.default.copyItem(at: logger.logURL, to: url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("View") { showLogViewer = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Clear") { logger.clearLog() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .sheet(isPresented: $showLogViewer) {
            LogViewerSheet()
        }
    }

    // MARK: - Helpers

    private func settingLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
    }

    private func settingRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.primary.opacity(0.7))
            Spacer()
            trailing()
        }
    }

    private func settingRow(_ label: some StringProtocol, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            trailing()
        }
    }
}

private struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Application Log")
                    .font(.headline)
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
