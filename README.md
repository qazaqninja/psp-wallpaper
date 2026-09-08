# PSP Wave

The PSP XMB background, alive on your macOS desktop. A single Metal fragment shader — glowing crests drifting over a gradient, ~0.5% CPU, no Electron, no App Store, one 260 KB binary.

<p align="center">
  <a href="https://github.com/qazaqninja/psp-wallpaper/releases/latest"><img alt="Downloads" src="https://img.shields.io/github/downloads/qazaqninja/psp-wallpaper/total?style=for-the-badge&label=downloads&color=b91c1c"></a>
  <a href="https://github.com/qazaqninja/psp-wallpaper/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/qazaqninja/psp-wallpaper?style=for-the-badge&color=b91c1c"></a>
  <a href="https://github.com/qazaqninja/psp-wallpaper/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/qazaqninja/psp-wallpaper?style=for-the-badge&color=b91c1c"></a>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-12%2B-black?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-black?style=for-the-badge">
</p>

![PSP Wave demo](docs/demo.gif)

*Four palettes, live-reloaded from `config.json` while it runs. Full-quality clips: [demo.mp4](docs/demo.mp4) · [demo-idle.mp4](docs/demo-idle.mp4)*

## Install

### Homebrew

```bash
brew tap qazaqninja/psp-wallpaper https://github.com/qazaqninja/psp-wallpaper
brew install psp-wallpaper
brew services start psp-wallpaper
```

`brew services` keeps it running and relaunches it at login.

### Direct download

Grab the tarball from [Releases](https://github.com/qazaqninja/psp-wallpaper/releases/latest), then:

```bash
tar xzf psp-wallpaper-*-arm64.tar.gz && xattr -d com.apple.quarantine PSPWallpaper && ./PSPWallpaper &
```

The `xattr` line is needed because the binary is unsigned — it strips the "downloaded from the internet" quarantine flag.

### From source

Needs Xcode Command Line Tools (`xcode-select --install`). This is the path for Intel Macs.

```bash
git clone https://github.com/qazaqninja/psp-wallpaper && cd psp-wallpaper
swiftc -O main.swift -o PSPWallpaper -framework Cocoa -framework MetalKit
./PSPWallpaper &
```

## Use

- **Menu bar wave icon → Settings…** — every knob, applied while you drag.
- **Quit** from the same menu (or `brew services stop psp-wallpaper`).
- `psp-wallpaper --preview` — draws over every window instead of on the desktop. Poor man's screensaver, and how the demos above were recorded.
- `psp-wallpaper --selftest` — asserts the shader/Swift struct layouts still match.

## Config

`~/.config/psp-wallpaper/config.json`, re-read within a second of saving, so any editor works as a live control surface. Every key is optional.

| Key | Range | What it does |
| --- | --- | --- |
| `colorTop` / `colorBottom` | `#rrggbb` | Background gradient ends |
| `waveColor` | `#rrggbb` | Tint of the water below each crest |
| `crestColor` | `#rrggbb` | The glowing line itself |
| `waveCount` | 1–5 | Number of stacked waves |
| `waveOpacity` | 0–1 | How much the wave darkens what's under it |
| `amplitude` | 0–0.4 | Wave height |
| `speed` | 0–2 | Drift rate |
| `crestGlow` | 0–2 | Bloom on the crest |
| `gradientAngle` | 0–360 | Gradient direction, degrees |
| `fps` | 10–60 | Frame cap — drop it to save battery |
| `renderScale` | 0.5–2 | Render resolution multiplier |

## Notes

- Picks the integrated GPU when there is one, and pauses entirely when the desktop is covered — a full-screen app costs it nothing.
- Handles monitors being plugged, unplugged and rearranged; only the windows that actually changed get rebuilt.
- Multi-monitor and multi-Space by design: one window per screen, on every Space.

## Uninstall

```bash
brew services stop psp-wallpaper && brew uninstall psp-wallpaper
rm -rf ~/.config/psp-wallpaper
```

MIT.
