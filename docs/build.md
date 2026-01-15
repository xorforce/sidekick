# sidekick build

Build iOS/macOS targets using `xcodebuild`, with optional pretty output via `xcpretty` if installed.

## Quick usage

```bash
# Use saved defaults from .sidekick/config.json
sidekick build

# Specify workspace and scheme explicitly
sidekick build --workspace MyApp.xcworkspace --scheme MyApp --platform ios-sim

# Device / macOS examples
sidekick build --project MyApp.xcodeproj --scheme MyApp --platform ios-device
sidekick build --project MyMacApp.xcodeproj --scheme MyMacApp --platform macos

# Clean + Release build
sidekick build --configuration Release --clean
```

## Flags

- `--workspace <path>`: Path to `.xcworkspace`.
- `--project <path>`: Path to `.xcodeproj` (used if workspace not provided).
- `--scheme <name>`: Scheme to build (required unless provided via config).
- `--configuration <name>`: Build configuration (default `Debug` or config default).
- `--platform <ios-sim|ios-device|macos>`: SDK/destination helper.
- `--clean`: Run `clean` before `build`.
- `--allow-provisioning-updates`: Allow Xcode to update provisioning profiles automatically.
- `--verbose`: Stream full `xcodebuild` output (skips spinner).

## Behavior

- Loads defaults from `.sidekick/config.json` in the current directory, then applies CLI flags as overrides.
- Runs `hooks.build.pre` before the build and `hooks.build.post` after a successful build (if set).
- Resolves `xcpretty` via `xcrun --find` and common paths; streams pretty output when available, otherwise prints raw `xcodebuild` output.
- Saves logs to `.sidekick/logs/build-<timestamp>/raw.log` and `pretty.log` (pretty falls back to raw if `xcpretty` is missing).
- Extracts error lines (`error:`) to surface failure reasons.

## Best practices

- Prefer workspaces (`--workspace`) when using CocoaPods/SwiftPM; otherwise pass `--project`.
- Keep schemes shared so CI/local builds behave the same.
- Set `--platform ios-sim` for simulator SDK; `ios-device` for connected device or generic destination; `macos` for macOS builds.
- Use `--clean` only when needed; it slows builds by removing DerivedData.
- Re-run `sidekick configure` when project structure/schemes change so defaults stay current.

## Do / Don't

- Do run from the directory containing `.sidekick/config.json` if you rely on saved defaults.
- Do install `xcpretty` (e.g., `gem install xcpretty`) for readable logs.
- Don’t mix `--workspace` and `--project`; pass only one.
- Don’t forget `--scheme`; `xcodebuild` will fail without it.

## Troubleshooting

- **Scheme not found**: ensure it’s shared and spelled exactly; verify with `xcodebuild -list`.
- **Build uses wrong defaults**: confirm you’re running in the intended directory or override via flags.
- **Pretty logs missing**: install `xcpretty` or ensure it’s on `PATH`/`xcrun --find` can locate it.
