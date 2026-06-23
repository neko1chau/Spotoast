import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var clientIdInput = ""
    @State private var editingClientId = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Spotoast")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Web Playback SDK · Spotify Premium")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if !authManager.hasClientId || editingClientId {
                clientIdSection
            } else {
                loginSection
            }

            Spacer()

            VStack(spacing: 4) {
                Text("Redirect URI: spotoast://callback")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if authManager.hasClientId && !editingClientId {
                    Button("Change Client ID") { editingClientId = true }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .buttonStyle(.borderless)
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { clientIdInput = authManager.clientId }
    }

    private var clientIdSection: some View {
        VStack(spacing: 12) {
            Text("Enter your Spotify Client ID")
                .font(.headline)

            Text("Create an app at developer.spotify.com")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Client ID", text: $clientIdInput)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)

            Button(action: {
                authManager.saveClientId(clientIdInput)
                editingClientId = false
            }) {
                Text("Save")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(clientIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var loginSection: some View {
        Button(action: { authManager.login() }) {
            HStack {
                Image(systemName: "person.fill")
                Text("Login with Spotify")
            }
            .font(.headline)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
    }
}
