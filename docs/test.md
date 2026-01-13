# sidekick test

Run Xcode tests using `xcodebuild test`, with optional test plan selection.

## Quick usage

```bash
# Use saved defaults from .sidekick/config.json
sidekick test

# Specify workspace and scheme explicitly
sidekick test --workspace MyApp.xcworkspace --scheme MyApp --platform ios-sim

# Select a specific test plan
sidekick test --scheme MyApp --platform ios-sim --test-plan CI

# Clean + test
sidekick test --clean
```

## Flags

- `--workspace <path>`: Path to `.xcworkspace`.
- `--project <path>`: Path to `.xcodeproj` (used if workspace not provided).
- `--scheme <name>`: Scheme to test (required unless provided via config).
- `--configuration <name>`: Build configuration (default `Debug` or config default).
- `--platform <ios-sim|ios-device|macos>`: SDK/destination helper.
- `--test-plan <name>`: Test plan name (mapped to `xcodebuild -testPlan <name>`).
- `--clean`: Run `clean` before `test`.

## Behavior

- Loads defaults from `.sidekick/config.json` in the current directory, then applies CLI flags as overrides.
- Test plan defaults are set via `sidekick init` (listed via `xcodebuild -showTestPlans`) and can be overridden with `--test-plan`.
- Saves logs to `.sidekick/logs/test-<timestamp>/raw.log` and `pretty.log` (pretty falls back to raw if `xcpretty` is missing).

## Troubleshooting

- **No test plans listed**: ensure your scheme has test plans configured and shared in Xcode.
- **Scheme not found**: ensure it’s shared; verify with `xcodebuild -list`.
- **Wrong defaults**: run from the directory containing `.sidekick/config.json` or override via flags.

