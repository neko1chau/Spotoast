import SwiftUI
import AppKit

final class MiniPlayerController {
    static let shared = MiniPlayerController()
    private var panel: NSPanel?

    func toggle(player: WebPlayerManager) {
        if let panel, panel.isVisible {
            panel.close()
            self.panel = nil
            return
        }
        let view = MiniPlayerContent()
            .environmentObject(player)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 48)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 48),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - 160
            let y = screen.visibleFrame.maxY - 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel
    }

    var isVisible: Bool { panel?.isVisible ?? false }
}

private struct MiniPlayerContent: View {
    @EnvironmentObject var player: WebPlayerManager
    @State private var currentLyric: String = "♪"
    @State private var lyricId: String = ""
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: URL(string: player.currentTrack?.imageUrl ?? "")) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.08))
            }
            .frame(width: 32, height: 32)
            .cornerRadius(6)

            Text(currentLyric)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(lyricId)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 6)),
                    removal: .opacity.combined(with: .offset(y: -6))
                ))

            if isHovered {
                Button {
                    MiniPlayerController.shared.toggle(player: player)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 48)
        .glassBackground(cornerRadius: 10, fallback: Color.black.opacity(0.75))
        .onHover { isHovered = $0 }
        .onChange(of: player.position) { _ in updateLyric() }
        .onChange(of: player.lyrics.count) { _ in
            currentLyric = "♪"
            lyricId = ""
        }
    }

    private func updateLyric() {
        guard player.isSyncedLyrics, !player.lyrics.isEmpty else {
            if currentLyric != "♪" {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentLyric = "♪"
                    lyricId = ""
                }
            }
            return
        }
        var best: LyricLine?
        for line in player.lyrics {
            if line.startTime <= player.position { best = line } else { break }
        }
        let newId = best.map { "\($0.id)" } ?? ""
        guard newId != lyricId else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentLyric = best?.words ?? "♪"
            lyricId = newId
        }
    }
}
