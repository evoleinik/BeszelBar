# BeszelBar

**Your Beszel servers at a glance from the menu bar.**

BeszelBar keeps your [Beszel](https://github.com/henrygd/beszel) infrastructure in view without opening a browser. Connect to your hubs and get a clear, glanceable dashboard for system health, resource usage, containers, and alerts right from the macOS menu bar.

## This fork (branch `agents`)

- **Live graphs in the menu bar.** One graph per machine, with a blue CPU line and a green RAM line. It subscribes to Beszel's `rt_metrics` realtime feed, the web UI's one-second feed. Readings are averaged into one point per 5 seconds, so each graph covers 5 minutes. Servers come first, then Macs. Each name reads bottom to top beside its graph, and graphs match Stats' height.
- **Agents section and waiting badge.** These read agent-exporter's custom metrics from `custom_stats`. That collection needs Beszel with henrygd/beszel#2562.
- **Checks.** Run `scripts/check-live.sh` for the stream parser, topic encoding, averaging and geometry. Run `scripts/check-agent-stats.sh [record.json]` for the agent metric parser.
- **Build and install.** Run `scripts/build-local.sh` on the Mac. It signs ad hoc with a fixed rule, the bundle id, so the keychain sees each rebuild as the same app and one "Always Allow" lasts. It works over SSH too.
- **HTTPS.** macOS blocks plain HTTP to an IP address, so give the hub an HTTPS URL, for example through `tailscale serve`.

## Installation

### Homebrew

```bash
brew install --cask loriage/tap/beszelbar
```

### Download

Download the latest release from the [Releases](https://github.com/Loriage/BeszelBar/releases) page.

The app is signed and notarized by Apple, so macOS should recognize it as a trusted build when you install it.

### Build from source

```bash
# Requires Xcode 15+ and xcodegen
brew install xcodegen
git clone https://github.com/Loriage/BeszelBar.git
cd BeszelBar
./build.sh
open build/Release/BeszelBar.app
```

## Screenshot

<img src="screenshot.png" width="50%" alt="BeszelBar Screenshot">

## Features

- **Live system cards** — See all your servers with status indicators, CPU, memory, and disk at a glance
- **Rich system details** — Hover for detailed metrics including temperature, uptime, and usage bars
- **Container monitoring** — View Docker containers with health status, resource usage, and image info
- **Alert notifications** — Active alerts displayed prominently with triggering conditions
- **Multi-hub support** — Connect multiple Beszel instances and switch between them instantly
- **Native performance** — Built with SwiftUI and AppKit for minimal resource usage
- **Secure authentication** — Credentials stored safely in macOS Keychain
- **Auto-refresh** — Configurable polling interval from 10 seconds to 5 minutes

## Setup

1. Launch BeszelBar
2. Click the menu bar icon and open **Settings**
3. Add your Beszel hub URL, email, and password
4. Your servers will appear in the menu bar dropdown

BeszelBar supports both password and JWT token authentication. Tokens are automatically refreshed when needed.

## Requirements

- macOS 14.0 (Sonoma) or later
- A running [Beszel](https://github.com/henrygd/beszel) hub instance

## Acknowledgements

A huge thank you to [henrygd](https://github.com/henrygd) for creating Beszel, a fantastic, lightweight, and open-source monitoring tool. This mobile client would not exist without his remarkable work.

## License

MIT License — see [LICENSE](LICENSE) for details.
