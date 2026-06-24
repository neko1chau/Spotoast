import Foundation
import AuthenticationServices
import CommonCrypto
import Combine

@MainActor
class AuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var refreshToken: String?
    @Published var isLoading = false
    @Published var error: String?

    /// Called whenever a new access token is obtained (initial auth or refresh).
    /// Wire this to `APIClient.updateToken()` to keep the API client in sync.
    var onTokenRefresh: ((String) -> Void)?

    private var session: ASWebAuthenticationSession?
    private var refreshTask: Task<Void, Never>?

    @Published var clientId: String = ""

    override init() {
        super.init()
        clientId = KeychainHelper.read(key: "client_id")
            ?? ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_ID"]
            ?? ""
        restoreTokens()
    }

    var hasClientId: Bool { !clientId.isEmpty }

    func saveClientId(_ id: String) {
        let newId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if newId != clientId {
            clearTokens()
            accessToken = nil
            refreshToken = nil
            isAuthenticated = false
        }
        clientId = newId
        KeychainHelper.save(key: "client_id", value: clientId)
    }
    private let redirectUri = "spotoast://callback"
    private let scopes = "streaming user-read-email user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private playlist-read-collaborative user-read-private user-library-read"

    private var codeVerifier: String?

    func login() {
        isLoading = true
        error = nil
        codeVerifier = generateCodeVerifier()
        guard let verifier = codeVerifier else {
            error = "Failed to generate code verifier"
            isLoading = false
            return
        }
        let challenge = generateCodeChallenge(from: verifier)

        guard let encodedScope = scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedRedirect = redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let authURL = URL(string:
                "https://accounts.spotify.com/authorize?" +
                "response_type=code" +
                "&client_id=\(clientId)" +
                "&scope=\(encodedScope)" +
                "&redirect_uri=\(encodedRedirect)" +
                "&code_challenge_method=S256" +
                "&code_challenge=\(challenge)"
        ) else {
            error = "Failed to build auth URL"
            isLoading = false
            return
        }

        session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "spotoast"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                if let error = error {
                    self?.error = error.localizedDescription
                    self?.isLoading = false
                    return
                }
                guard let callbackURL = callbackURL else {
                    self?.error = "No callback URL"
                    self?.isLoading = false
                    return
                }
                let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
                if let spotifyError = components?.queryItems?.first(where: { $0.name == "error" })?.value {
                    self?.error = "Spotify: \(spotifyError)"
                    self?.isLoading = false
                    return
                }
                guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
                    self?.error = "No authorization code in: \(callbackURL.absoluteString)"
                    self?.isLoading = false
                    return
                }
                await self?.exchangeCodeForToken(code)
            }
        }

        session?.presentationContextProvider = self
        session?.start()
    }

    @discardableResult
    func refreshAccessToken() async -> Bool {
        guard let storedRefresh = refreshToken else { return false }
        let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=refresh_token&refresh_token=\(storedRefresh.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? storedRefresh)&client_id=\(clientId)"
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let errJson = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data), errJson.error != nil {
                let msg = errJson.errorDescription ?? errJson.error ?? "Token refresh failed"
                self.error = msg
                logger.error("Token refresh failed: \(msg)")
                if errJson.error == "invalid_grant" {
                    logger.warn("invalid_grant — logging out")
                    logout()
                }
                return false
            }
            let json = try JSONDecoder().decode(TokenResponse.self, from: data)
            accessToken = json.accessToken
            if let newRefresh = json.refreshToken { refreshToken = newRefresh }
            isAuthenticated = true
            persistTokens()
            logger.info("Token refreshed successfully")
            if let token = accessToken {
                onTokenRefresh?(token)
            }
            return true
        } catch {
            self.error = error.localizedDescription
            logger.error("Token refresh error: \(error.localizedDescription)")
            return false
        }
    }

    private func refreshWithRetry() async {
        var delay: UInt64 = 2_000_000_000
        let maxDelay: UInt64 = 60_000_000_000
        for _ in 0..<3 {
            guard !Task.isCancelled else { return }
            if await refreshAccessToken() { return }
            try? await Task.sleep(nanoseconds: delay)
            delay = min(delay * 2, maxDelay)
        }
    }

    func logout() {
        refreshTask?.cancel()
        refreshTask = nil
        accessToken = nil
        refreshToken = nil
        isAuthenticated = false
        error = nil
        isLoading = false
        clearTokens()
        logger.info("User logged out")
    }

    private func restoreTokens() {
        if let token = KeychainHelper.read(key: "access_token"),
           let refresh = KeychainHelper.read(key: "refresh_token") {
            accessToken = token
            refreshToken = refresh
            isAuthenticated = true
            startTokenRefresh()
            Task { [weak self] in
                let success = await self?.refreshAccessToken() ?? false
                if !success {
                    self?.logout()
                }
            }
        }
    }

    private func persistTokens() {
        if let token = accessToken { KeychainHelper.save(key: "access_token", value: token) }
        if let refresh = refreshToken { KeychainHelper.save(key: "refresh_token", value: refresh) }
    }

    private func clearTokens() {
        KeychainHelper.delete(key: "access_token")
        KeychainHelper.delete(key: "refresh_token")
    }

    private func exchangeCodeForToken(_ code: String) async {
        let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        guard let verifier = codeVerifier else {
            error = "Missing code verifier"
            isLoading = false
            return
        }

        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(redirectUri)",
            "client_id=\(clientId)",
            "code_verifier=\(verifier)"
        ].joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let errJson = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data), errJson.error != nil {
                self.error = errJson.errorDescription ?? errJson.error ?? "Token exchange failed"
                isLoading = false
                return
            }
            let json = try JSONDecoder().decode(TokenResponse.self, from: data)
            accessToken = json.accessToken
            refreshToken = json.refreshToken
            isAuthenticated = true
            isLoading = false
            persistTokens()
            if let token = accessToken {
                onTokenRefresh?(token)
            }
            startTokenRefresh()
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    private func startTokenRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            var refreshCount = 0
            let maxRefreshCount = 2880  // 30 min × 2880 = 60 days
            while !Task.isCancelled, refreshCount < maxRefreshCount {
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
                await self?.refreshWithRetry()
                refreshCount += 1
            }
        }
    }

    private func generateCodeVerifier() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<128).map { _ in chars.randomElement()! })
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct OAuthErrorResponse: Codable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
