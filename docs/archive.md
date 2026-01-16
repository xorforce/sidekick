# sidekick archive

Archive an iOS device or macOS app using `xcodebuild archive`.

## Quick usage

```bash
# Use saved defaults from .sidekick/config.json
sidekick archive

# Specify workspace and scheme explicitly
sidekick archive --workspace MyApp.xcworkspace --scheme MyApp --platform ios-device

# macOS example
sidekick archive --project MyMacApp.xcodeproj --scheme MyMacApp --platform macos

# Custom output directory or explicit .xcarchive
sidekick archive --output ./archives
sidekick archive --output ./MyApp.xcarchive
```

## Flags

- `--path <dir>`: Directory to run in (where `.sidekick/config.json` is expected).
- `--workspace <path>`: Path to `.xcworkspace`.
- `--project <path>`: Path to `.xcodeproj` (used if workspace not provided).
- `--scheme <name>`: Scheme to archive (required unless provided via config).
- `--configuration <name>`: Build configuration (default `Release` or config default).
- `--platform <ios-device|macos>`: SDK/destination helper (archives do not support `ios-sim`).
- `--config <path>`: Path to a Sidekick config file (overrides `.sidekick/config.json`).
- `--output <path>`: Directory or `.xcarchive` path for output.
- `--derived-data <path>`: Derived data path.
- `--clean`: Run `clean` before `archive`.
- `--allow-provisioning-updates`: Allow Xcode to update provisioning profiles automatically.
- `--verbose`: Stream full `xcodebuild` output (skips spinner).

## Behavior

- Loads defaults from `.sidekick/config.json` in the current directory (or `--config`), then applies CLI flags as overrides.
- Runs `hooks.archive.pre` before archiving and `hooks.archive.post` after a successful archive (if set).
- If `--output` is a directory, a timestamped `<scheme>-<timestamp>.xcarchive` is created inside it.
- If `--output` ends in `.xcarchive`, that path is used directly.

## Troubleshooting

- **Provisioning profile errors**: Re-run with `--allow-provisioning-updates` or set it via `sidekick configure`.
- **Archive never finishes**: Re-run with `--verbose` to stream output and surface Xcode progress.
