import SwiftUI

@main
struct SpotoastApp: App {
    @StateObject private var authManager = AuthManager()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.auto

    var body: some Scene {
        WindowGroup("Spotoast") {
            ContentView()
                .environmentObject(authManager)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear { appearanceMode.apply() }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
    }
}
