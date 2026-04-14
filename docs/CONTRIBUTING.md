# Contributing

Thanks for taking the time to contribute to Mac Coffee.

Please note we have a [code of conduct](CODE_OF_CONDUCT.md), and we expect all contributors to follow it.

## Development environment setup

1. Clone the repository:

   ```sh
   git clone https://github.com/Elliotwu-7/Mac-Coffee.git
   cd Mac-Coffee
   ```

2. Make sure Xcode Command Line Tools are available:

   ```sh
   xcode-select -p
   ```

3. Build and install locally:

   ```sh
   chmod +x build.sh install.sh package_dmg.sh
   ./build.sh
   ./install.sh
   ```

4. If you are changing release packaging, generate a DMG before opening the PR:

   ```sh
   ./package_dmg.sh
   ```

## Issues and feature requests

Found a bug, packaging issue, or UX problem? Please [open an issue](https://github.com/Elliotwu-7/Mac-Coffee/issues) and include:

- macOS version
- whether the machine was on battery or AC power
- whether the privileged helper had already been installed
- exact steps to reproduce

## Pull requests

1. Fork the project
2. Create a branch (`git checkout -b feat/my-change`)
3. Commit using [Conventional Commits](https://www.conventionalcommits.org)
4. Push your branch
5. Open a pull request

Please keep pull requests focused and include testing notes when behavior changes.
