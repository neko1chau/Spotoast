# Spotoast

A native macOS Spotify client built with SwiftUI and the Spotify Web Playback SDK.

## Features

- Spotify Connect playback via Web Playback SDK
- Playlist browsing, Liked Songs, search, artist & album pages
- Synced lyrics display (powered by [LRCLIB](https://lrclib.net) + NetEase Music)
- Full-screen now playing view with immersive title bar
- Floating mini player with real-time lyrics
- Media key support (play/pause/next/prev)
- Now Playing integration (macOS media widget)
- Queue management with drag-to-reorder
- Playlist & lyrics disk cache with offline fallback
- Simple sidebar mode (shows Liked Songs directly)
- Liquid Glass effects on macOS 26+
- Dark mode support (Auto / Light / Dark)
- Application logging for diagnostics (Settings → Logs)
- Keyboard shortcuts (Space, Arrow keys)

## Requirements

- macOS 13+
- Swift 5.9+
- Spotify Premium account

## Setup

1. Go to [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and create a new app.
2. **Under "APIs used", make sure both `Web API` and `Web Playback SDK` are enabled.** Without this, playback will not work.
3. Add `spotoast://callback` as a Redirect URI in your app settings.
4. Copy your **Client ID**.

## Build & Run

```bash
swift build
swift run Spotoast
```

To build a universal binary (Apple Silicon + Intel):

```bash
swift build --arch arm64 --arch x86_64
```

If macOS shows "Spotoast is damaged and can't be opened", run:

```bash
xattr -cr /Applications/Spotoast.app
```

On first launch, paste your Client ID into the setup screen and click Save, then log in with your Spotify account.

## License

MIT
