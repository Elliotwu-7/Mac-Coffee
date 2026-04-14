<h1 align="center">
  <a href="https://github.com/Elliotwu-7/Mac-Coffee">
    <img src="docs/images/logo.png" alt="Mac Coffee logo" width="100" height="100">
  </a>
</h1>

<div align="center">
  Mac Coffee
  <br />
  A native macOS menu bar app for keeping your Mac awake, restoring normal sleep on a schedule, and falling back safely when running on battery.
  <br />
  <br />
  <a href="https://github.com/Elliotwu-7/Mac-Coffee/releases">Download DMG</a>
  ·
  <a href="https://github.com/Elliotwu-7/Mac-Coffee/issues/new?assignees=&labels=bug&template=01_BUG_REPORT.md&title=bug%3A+">Report a Bug</a>
  ·
  <a href="https://github.com/Elliotwu-7/Mac-Coffee/issues/new?assignees=&labels=enhancement&template=02_FEATURE_REQUEST.md&title=feat%3A+">Request a Feature</a>
</div>

<div align="center">
<br />

[![Project license](https://img.shields.io/github/license/Elliotwu-7/Mac-Coffee.svg?style=flat-square)](LICENSE)
[![Pull Requests welcome](https://img.shields.io/badge/PRs-welcome-ff69b4.svg?style=flat-square)](https://github.com/Elliotwu-7/Mac-Coffee/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22)
[![code with love by Elliotwu-7](https://img.shields.io/badge/%3C%2F%3E%20with%20%E2%99%A5%20by-Elliotwu-7-ff1414.svg?style=flat-square)](https://github.com/Elliotwu-7)

</div>

<details open="open">
<summary>Table of Contents</summary>

- [About](#about)
  - [Built With](#built-with)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Usage](#usage)
- [Roadmap](#roadmap)
- [Support](#support)
- [Project assistance](#project-assistance)
- [Contributing](#contributing)
- [Authors & contributors](#authors--contributors)
- [Security](#security)
- [License](#license)
- [Acknowledgements](#acknowledgements)

</details>

---

## About

Mac Coffee is a native menu bar utility for macOS that lets you switch between a "keep awake" mode and the system's normal sleep behavior without opening Terminal. It is designed for people who occasionally need to prevent clamshell sleep, but still want clear safety rails around timers, battery usage, and login startup.

### Built With

- SwiftUI
- AppKit
- IOKit power source APIs
- `pmset` via a privileged helper for sleep state changes
- Shell scripts for build, install, and DMG packaging

## Getting Started

### Prerequisites

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)
- Administrator approval on first use to install the helper

### Installation

Install from a release DMG:

1. Download `MacCoffee.dmg` from the latest GitHub release.
2. Open the DMG.
3. Drag `Mac Coffee.app` into `Applications`.
4. Launch `Mac Coffee.app` from `Applications`.

Build from source:

```sh
cd /Users/elliotwu/MacCoffee
chmod +x build.sh install.sh package_dmg.sh
./build.sh
./install.sh
```

Create a DMG locally:

```sh
./package_dmg.sh
open dist/MacCoffee.dmg
```

## Usage

Mac Coffee lives in the menu bar and supports:

- Toggling between keep-awake mode and normal sleep
- Scheduled return to normal sleep with presets or a specific date and time
- Optional "restore sleep immediately on battery power" protection
- Login-at-startup toggle
- One-time privileged helper installation so repeat toggles do not keep asking for a password

On first switch, macOS will ask for administrator approval to install the helper. After that, future toggles should not prompt again unless the helper is removed.

## Roadmap

See the [open issues](https://github.com/Elliotwu-7/Mac-Coffee/issues) for a list of proposed features (and known issues).

- Polish the release workflow and automate DMG publishing
- Add local notifications for timer completion and battery-triggered recovery
- Expand diagnostics around sleep-state detection on more Mac models

## Support

- Open a [GitHub issue](https://github.com/Elliotwu-7/Mac-Coffee/issues/new?assignees=&labels=question&template=04_SUPPORT_QUESTION.md&title=support%3A+)
- Use the contact options listed on [Elliotwu-7's GitHub profile](https://github.com/Elliotwu-7)

## Project assistance

If you want to support Mac Coffee:

- Star the repository
- Share feedback through issues
- Open pull requests for UX, packaging, or documentation improvements

## Contributing

Please read [our contribution guidelines](docs/CONTRIBUTING.md), and thank you for being involved.

## Authors & contributors

The original setup of this repository is by [Elliot Wu](https://github.com/Elliotwu-7).

For a full list of all authors and contributors, see [the contributors page](https://github.com/Elliotwu-7/Mac-Coffee/contributors).

## Security

Mac Coffee follows good practices of security, but 100% security cannot be assured. Mac Coffee is provided **"as is"** without any **warranty**. Use at your own risk.

_For more information and to report security issues, please refer to our [security documentation](docs/SECURITY.md)._

## License

This project is licensed under the **MIT license**.

See [LICENSE](LICENSE) for more information.

## Acknowledgements

- [dec0dOS/amazing-github-template](https://github.com/dec0dOS/amazing-github-template)
- Apple's macOS developer tools and system frameworks
- The icon assets provided in `AppAssets_2026-04-14.zip`
