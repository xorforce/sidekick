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
  - Scans for `.xcworkspace` / `.xcodeproj`, selects scheme/config/platform/test plan, saves defaults to `.sidekick/config.json`.
- `sidekick build [--workspace <path>|--project <path>] --scheme <name> [--configuration <cfg>] [--platform ios-sim|ios-device|macos] [--clean]`
  - Builds using flags or saved defaults; logs go to `.sidekick/logs/` (pretty if `xcpretty` is available).
- `sidekick test [--workspace <path>|--project <path>] --scheme <name> [--configuration <cfg>] [--platform ios-sim|ios-device|macos] [--test-plan <plan>] [--clean]`
  - Runs tests using flags or saved defaults; logs go to `.sidekick/logs/` (pretty if `xcpretty` is available).

## Common flows

```bash
# Onboard a project interactively (from project root)
sidekick init

# Onboard from elsewhere
sidekick init --path /path/to/MyApp

# Build using saved defaults
sidekick build

# Run tests using saved defaults
sidekick test

# Override saved defaults
sidekick build --scheme MyApp --configuration Release --platform ios-sim --clean
sidekick test --scheme MyApp --platform ios-sim --test-plan CI
```

## Development

```bash
swift build          # compile
swift run sidekick   # run CLI
swift test           # Swift Package tests (not Xcodebuild tests)
```

## Docs

See `docs/` for per-command guides and best practices.

## License

MIT
