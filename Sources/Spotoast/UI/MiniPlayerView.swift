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
        hostingView.frame = NSRect(x: 0, y: 0, width: 340, height: 80)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 80),
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
            let x = screen.visibleFrame.maxX - 360
            let y = screen.visibleFrame.maxY - 100
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel
    }

    var isVisible: Bool { panel?.isVisible ?? false }
}

private struct MiniPlayerContent: View {
    @EnvironmentObject var player: WebPlayerManager
    @State private var currentLyric: String?
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 12) {
                CachedAsyncImage(url: URL(string: player.currentTrack?.imageUrl ?? "")) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                }
                .frame(width: 48, height: 48)
                .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    if let track = player.currentTrack {
                        Text(track.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artists)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Not Playing")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    if let lyric = currentLyric {
                        Text(lyric)
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    miniBtn("backward.fill", size: 11) { player.previousTrack() }
                    miniBtn(player.isPaused ? "play.fill" : "pause.fill", size: 14) { player.togglePlay() }
                    miniBtn("forward.fill", size: 11) { player.nextTrack() }
                }

                Button {
                    MiniPlayerController.shared.toggle(player: player)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 13)

            GeometryReader { geo in
                let pct = player.duration > 0 ? player.position / player.duration : 0
                Rectangle()
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: geo.size.width * pct, height: 2)
            }
            .frame(height: 2)
            .clipped()
        }
        .frame(width: 340, height: 80)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: player.position) { _ in updateLyric() }
        .onChange(of: player.lyrics.count) { _ in updateLyric() }
    }

    private func miniBtn(_ name: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: size))
        }
        .buttonStyle(.borderless)
        .foregroundColor(.primary)
    }

    private func updateLyric() {
        guard player.isSyncedLyrics, !player.lyrics.isEmpty else {
            currentLyric = nil
            return
        }
        var best: LyricLine?
        for line in player.lyrics {
            if line.startTime <= player.position { best = line } else { break }
        }
        currentLyric = best?.words
    }
}
