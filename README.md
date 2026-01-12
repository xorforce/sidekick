# Sidekick

A minimal Swift CLI for building, running, and testing iOS/macOS apps.

## Quick start

```bash
# Install deps and build
swift build

# CLI help
swift run sidekick --help
```

## Commands (concise)

- `sidekick init [--path <dir>] [--non-interactive]` — detect .xcworkspace/.xcodeproj, choose scheme/config/platform, save defaults to `.sidekick/config.json`.
- `sidekick build [--workspace|--project] --scheme <name> [--configuration <cfg>] [--platform ios-sim|ios-device|macos] [--clean]` — build using flags or saved defaults; logs saved under `.sidekick/logs/`.

## Common flows

```bash
# Onboard a project interactively (from project root)
swift run sidekick init

# Onboard from elsewhere
swift run sidekick init --path /path/to/MyApp

# Build using saved defaults
swift run sidekick build

# Override saved defaults
swift run sidekick build --scheme MyApp --configuration Release --platform ios-sim --clean
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
