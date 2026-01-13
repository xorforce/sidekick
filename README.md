# Sidekick 🦿

A minimal Swift CLI for building, running, and testing iOS/macOS apps.

## Install

```bash
brew tap xorforce/tap
brew install xorforce/tap/sidekick
```

## Quick start

```bash
# See CLI help
sidekick --help
```

## Commands

- `sidekick init [--path <dir>] [--non-interactive]`
  - Scans for `.xcworkspace` / `.xcodeproj`, selects scheme/config/platform, optionally selects a default simulator/device, saves defaults to `.sidekick/config.json`.
- `sidekick build [--workspace <path>|--project <path>] --scheme <name> [--configuration <cfg>] [--platform ios-sim|ios-device|macos] [--clean]`
  - Builds using flags or saved defaults; logs go to `.sidekick/logs/` (pretty if `xcpretty` is available).
- `sidekick sim`
  - Lists available simulators (via `xcrun simctl list`).
- `sidekick devices`
  - Lists physical devices known to Xcode (via `xcrun xcdevice list`).

## Common flows

```bash
# Onboard a project interactively (from project root)
sidekick init

# Onboard from elsewhere
sidekick init --path /path/to/MyApp

# Build using saved defaults
sidekick build

# Override saved defaults
sidekick build --scheme MyApp --configuration Release --platform ios-sim --clean
```

## Development

```bash
swift build          # compile
swift run sidekick   # run CLI
swift test           # tests (placeholder)
```

## Docs

See `docs/` for per-command guides and best practices.

## License

MIT
