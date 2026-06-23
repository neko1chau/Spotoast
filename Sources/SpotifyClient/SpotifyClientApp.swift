import SwiftUI

@main
struct SpotoastApp: App {
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup("Spotoast") {
            ContentView()
                .environmentObject(authManager)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
    }
}
