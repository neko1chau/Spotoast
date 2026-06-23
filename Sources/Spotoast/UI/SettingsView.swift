import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var updateManager = UpdateManager()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.auto
    var onLogout: (() -> Void)?
    @State private var editingClientId = false
    @State private var clientIdInput = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                aboutHeader
                card { appearanceContent }
                card { updateContent }
                card { accountContent }
                Spacer().frame(height: 8)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            clientIdInput = authManager.clientId
            if updateManager.checkForUpdates {
                Task { await updateManager.checkForUpdate() }
            }
        }
    }

    // MARK: - Card wrapper

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.04))
        .cornerRadius(10)
    }

    // MARK: - About

    private var aboutHeader: some View {
        VStack(spacing: 8) {
            if let iconURL = Bundle.module.url(forResource: "Spotoast", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }

            Text("Spotoast")
                .font(.system(size: 20, weight: .semibold))

            Text("v\(UpdateManager.currentVersion)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(.primary.opacity(0.05))
                .cornerRadius(4)

            Link(destination: URL(string: "https://github.com/neko1chau/Spotoast")!) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                    Text("GitHub")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    // MARK: - Appearance

    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Appearance", systemImage: "paintbrush")
                .font(.system(size: 13, weight: .semibold))

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

    // MARK: - Updates

    private var updateContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))

            Toggle("Check automatically", isOn: $updateManager.checkForUpdates)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13))

            if updateManager.isChecking {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.5)
                    Text("Checking...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            } else if updateManager.hasUpdate, let version = updateManager.latestVersion {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("v\(version) available")
                            .font(.system(size: 12, weight: .medium))
                    }
                    Spacer()
                    if updateManager.isDownloading {
                        ProgressView().scaleEffect(0.5)
                    } else {
                        Button("Update") {
                            Task { await updateManager.downloadAndInstall() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.mini)
                    }
                }
            } else if updateManager.latestVersion != nil {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 11))
                    Text("Up to date")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            if let error = updateManager.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            Button("Check Now") {
                Task { await updateManager.checkForUpdate() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(updateManager.isChecking)
        }
    }

    // MARK: - Account

    private let privacyNote = "Credentials are stored locally and never uploaded."

    private var accountContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Account", systemImage: "person.circle")
                .font(.system(size: 13, weight: .semibold))

            if editingClientId {
                HStack(spacing: 8) {
                    TextField("Client ID", text: $clientIdInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    Button("Save") {
                        authManager.saveClientId(clientIdInput)
                        editingClientId = false
                    }
                    .controlSize(.mini)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel") {
                        clientIdInput = authManager.clientId
                        editingClientId = false
                    }
                    .controlSize(.mini)
                }
            } else {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(authManager.clientId.prefix(12) + "••••")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Edit") { editingClientId = true }
                        .controlSize(.mini)
                        .font(.system(size: 12))
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                Text(privacyNote)
                    .font(.system(size: 11))
            }
            .foregroundColor(.secondary.opacity(0.7))

            Divider().padding(.vertical, 4)

            Button(role: .destructive) {
                onLogout?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 11))
                    Text("Logout")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.red.opacity(0.8))
        }
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
