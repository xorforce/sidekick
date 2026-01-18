# sidekick test

Run xcodebuild tests for simulator, device, or macOS.

## Quick usage

```bash
# Use saved defaults from .sidekick/config.json
sidekick test

# Run from elsewhere
sidekick test --path /path/to/MyApp

# Force a specific platform
sidekick test --platform ios-sim

# Use a named test plan or .xctestplan file
sidekick test --test-plan MyPlan
sidekick test --test-plan ./Tests/MyApp.xctestplan
```

## Flags

- `--path <dir>`: Directory to run in (where `.sidekick/config.json` is expected). Defaults to current directory.
- `--config <path>`: Path to a Sidekick config file (overrides `.sidekick/config.json`).
- `--workspace <path>` / `--project <path>`: Explicit Xcode container override.
- `--scheme <name>`: Scheme override.
- `--configuration <name>`: Configuration override (default `Debug`).
- `--platform <ios-sim|ios-device|macos>`: SDK/destination helper.
- `--test-plan <plan>`: Test plan name or `.xctestplan` path.
- `--derived-data <path>`: Derived data path.
- `--clean`: Run `clean` before `test`.
- `--allow-provisioning-updates`: Allow Xcode to update provisioning profiles automatically.
- `--verbose`: Stream full `xcodebuild` output (skips spinner).

## Target selection logic

- If platform is `macos`: uses `platform=macOS`.
- For `ios-device`, Sidekick uses a configured device **only if** it is currently connected via USB.
- If no eligible device is available, Sidekick falls back to a configured simulator, then any available iPhone simulator.

## Behavior

- Loads defaults from `.sidekick/config.json` in the current directory (or `--config`), then applies CLI flags as overrides.
- Runs `hooks.test.pre` before the tests and `hooks.test.post` after a successful run (if set).
- Parses `xcodebuild` output to summarize passed/failed test cases.

## Notes / troubleshooting

- **No test plan found**: if the path is missing, Sidekick will warn and still pass the plan name to `xcodebuild`.
- **Device not connected**: `ios-device` will fall back to a simulator automatically.
- **Defaults not applied**: ensure you run in the directory containing `.sidekick/config.json` or pass `--path`.
