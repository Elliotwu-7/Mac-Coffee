<h1 align="center">
  <a href="https://github.com/Elliotwu-7/Mac-Coffee">
    <img src="docs/images/logo.png" alt="Mac Coffee logo" width="100" height="100">
  </a>
</h1>

<div align="center">
  Mac Coffee
  <br />
  A native macOS menu bar app that keeps your Mac awake, restores normal sleep on a schedule, and safely falls back when your Mac switches to battery power.
  <br />
  <br />
  <a href="README.zh-CN.md">中文文档</a>
  ·
  <a href="https://github.com/Elliotwu-7/Mac-Coffee/releases">Download DMG</a>
  ·
  <a href="https://github.com/Elliotwu-7/Mac-Coffee/issues/new?assignees=&labels=bug&template=01_BUG_REPORT.md&title=bug%3A+">Report a Bug</a>
  ·
  <a href="https://github.com/Elliotwu-7/Mac-Coffee/issues/new?assignees=&labels=enhancement&template=02_FEATURE_REQUEST.md&title=feat%3A+">Request a Feature</a>
</div>

<div align="center">
<br />

[![Project license](https://img.shields.io/github/license/Elliotwu-7/Mac-Coffee.svg?style=flat-square)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Elliotwu-7/Mac-Coffee?style=flat-square)](https://github.com/Elliotwu-7/Mac-Coffee/releases)
[![Pull Requests welcome](https://img.shields.io/badge/PRs-welcome-ff69b4.svg?style=flat-square)](https://github.com/Elliotwu-7/Mac-Coffee/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22)

</div>

## About

Mac Coffee is a lightweight native utility for macOS that lets you switch between a "keep awake" mode and the system's normal sleep behavior without touching Terminal. It is built for the everyday cases where you want a simple menu bar toggle, but still want sensible guardrails like timed recovery, a battery safety switch, and login startup support.

## Screenshot

![Mac Coffee screenshot](docs/images/screenshot.png)

## Features

- Native menu bar experience with a compact status area and clean context menu
- Toggle between keep-awake mode and normal sleep in one click
- Restore normal sleep after a preset duration or at a chosen date and time
- Optionally restore sleep immediately when the Mac starts running on battery
- Login-at-startup toggle
- One-time privileged helper installation so future toggles do not keep prompting for a password

## Installation

### Download the app

1. Download `MacCoffee.dmg` from the latest [GitHub release](https://github.com/Elliotwu-7/Mac-Coffee/releases).
2. Open the DMG.
3. Drag `Mac Coffee.app` into `Applications`.
4. Launch `Mac Coffee.app` from `Applications`.

If macOS says the app is "damaged" or cannot be opened, that is usually Gatekeeper blocking an unsigned build. You can remove the quarantine flag and try again:

```sh
sudo xattr -rd com.apple.quarantine /Applications/"Mac Coffee.app"
```

You can also open `System Settings > Privacy & Security`, then allow the blocked app and relaunch it.

### Build from source

Requirements:

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)
- Administrator approval on first use to install the helper

```sh
cd /Users/elliotwu/MacCoffee
chmod +x build.sh install.sh package_dmg.sh
./build.sh
./install.sh
```

To build a DMG locally:

```sh
./package_dmg.sh
open dist/MacCoffee.dmg
```

## Usage

Mac Coffee lives in the menu bar and is designed to stay out of the way:

- Turn keep-awake mode on when you need your Mac to stay active
- Choose a timer or a specific date and time to return to normal sleep
- Enable battery protection if you want Mac Coffee to immediately restore sleep when AC power is removed
- Enable launch at login if you want the utility available after every boot

On the first toggle, macOS will ask for administrator approval to install the helper. Once installed, later toggles should work without repeated password prompts unless the helper is removed.

## Release automation

This repository includes a GitHub Actions workflow that automatically builds the app and uploads `MacCoffee.dmg` whenever a tag like `v1.0.1` is pushed.

## Contributing

Issues, ideas, and pull requests are all welcome. Please check [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) if you want to contribute.

## Security

Mac Coffee is provided **as is** without warranty. If you discover a security issue, please follow the process described in [docs/SECURITY.md](docs/SECURITY.md).

## License

This project is released under the [MIT License](LICENSE).

## Thanks

- [dec0dOS/amazing-github-template](https://github.com/dec0dOS/amazing-github-template)
- Apple's macOS developer tools and system frameworks
- The icon assets provided in `AppAssets_2026-04-14.zip`
- Thanks to the [Linux.do](https://linux.do/) community for feedback, discussion, and early support
