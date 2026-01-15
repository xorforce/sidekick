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

## Config

Sidekick reads `.sidekick/config.json` from the current working directory. You can add pre/post hooks per command (build/run/archive) and a one-time setup job.

```json
{
  "hooks": {
    "build": {
      "pre": { "command": "bash", "args": ["./scripts/hook-echo.sh"] },
      "post": { "command": "bash", "args": ["./scripts/hook-echo.sh"] }
    },
    "run": {
      "pre": { "command": "bash", "args": ["./scripts/hook-echo.sh"] }
    }
  },
  "setupJob": {
    "pre": { "command": "bash", "args": ["./scripts/hook-echo.sh"] }
  }
}
```

There is a sample script at `scripts/hook-echo.sh` that only echoes, useful for testing.

## Commands

- `sidekick configure [--path <dir>] [--non-interactive] [--allow-provisioning-updates] [--archive-output <path>]`
  - Scans for `.xcworkspace` / `.xcodeproj`, selects scheme/config/platform, optionally selects a default simulator/device, saves defaults to `.sidekick/config.json`.
- `sidekick setup [--path <dir>]`
  - Runs the one-time setup job (if configured) and marks it complete.
- `sidekick build [--workspace <path>|--project <path>] --scheme <name> [--configuration <cfg>] [--platform ios-sim|ios-device|macos] [--clean] [--allow-provisioning-updates] [--verbose]`
  - Builds using flags or saved defaults; logs go to `.sidekick/logs/` (pretty if `xcpretty` is available).
- `sidekick archive [--path <dir>] [--workspace <path>|--project <path>] [--scheme <name>] [--configuration <cfg>] [--platform ios-device|macos] [--output <path>] [--derived-data <path>] [--clean] [--allow-provisioning-updates] [--verbose]`
  - Archives to an `.xcarchive` with destination defaults from config; supports provisioning updates and verbose output.
- `sidekick run [--path <dir>] [--workspace <path>|--project <path>] [--scheme <name>] [--configuration <cfg>] [--clean] [--simulator] [--allow-provisioning-updates] [--verbose]`
  - Builds, installs, and launches on **USB-connected** device if configured + connected; otherwise uses configured simulator; otherwise picks any available iPhone simulator.
- `sidekick sim`
  - Lists available simulators (via `xcrun simctl list`).
- `sidekick devices`
  - Lists physical devices known to Xcode (via `xcrun xcdevice list`).

## Common flows

```bash
# Configure a project interactively (from project root)
sidekick configure

# Configure from elsewhere
sidekick configure --path /path/to/MyApp

# Build using saved defaults
sidekick build

# Archive using saved defaults
sidekick archive

# Build + run using saved defaults
sidekick run

# Override saved defaults
sidekick build --scheme MyApp --configuration Release --platform ios-sim --clean

# Run for a project from elsewhere
sidekick run --path /path/to/MyApp

# Archive to a custom path
sidekick archive --output ./archives

# Force simulator (skip device selection)
sidekick run --simulator
```

## Development

```bash
swift build          # compile
swift run sidekick   # run CLI
swift test           # tests (placeholder)
```

## Docs

See `docs/` for per-command guides and best practices (`build`, `run`, `archive`, `setup`).

## License

MIT
