# sidekick run

Build, install, and launch an iOS app on a device or simulator.

## Quick usage

```bash
# From project root (uses .sidekick/config.json if present)
sidekick run

# From elsewhere
sidekick run --path /path/to/MyApp

# Force simulator even if device is configured
sidekick run --simulator

# Clean build
sidekick run --clean
```

## Flags

- `--path <dir>`: Directory to run in (where `.sidekick/config.json` is expected). Defaults to current directory.
- `--config <path>`: Path to a Sidekick config file (overrides `.sidekick/config.json`).
- `--workspace <path>` / `--project <path>`: Explicit Xcode container override.
- `--scheme <name>`: Scheme override.
- `--configuration <name>`: Configuration override (default `Debug`).
- `--clean`: Run `xcodebuild clean build`.
- `--simulator`: Skip device selection and run on simulator.
- `--allow-provisioning-updates`: Allow Xcode to update provisioning profiles automatically.
- `--verbose`: Stream full `xcodebuild` output (skips spinner).

## Target selection logic

- If `--simulator` is set: **always** use simulator.
- Otherwise, if a device is configured in `.sidekick/config.json`:
  - Sidekick only targets the device if it is **currently connected via USB**.
  - Devices paired over Wi‑Fi / local network are **ignored for now**.
- If no eligible device is available:
  - Use the configured simulator (if present)
  - Else select any available iPhone simulator (prefers already-booted, then newest runtime)

## Behavior

- Runs `hooks.run.pre` before any build/install steps and `hooks.run.post` after a successful run (if set).

## What it does

1) Builds via `xcodebuild` for the chosen destination.  
2) Locates the `.app` from `xcodebuild -showBuildSettings` (`BUILT_PRODUCTS_DIR` + `FULL_PRODUCT_NAME`).  
3) Installs and launches:
   - Simulator: `xcrun simctl install` + `xcrun simctl launch`
   - Device: `xcrun devicectl device install app` + `xcrun devicectl device process launch`

## Notes / troubleshooting

- **“Launch succeeded but I don’t see the app” (simulator)**: Sidekick attempts to open the Simulator app and select the UDID; if your Simulator app is closed/minimized, bring it to front and re-run.
- **Provisioning failures on device**: Ensure your signing/provisioning profile includes the device UDID and that the scheme is configured for the selected team.
- **Provisioning prompts or profile errors**: Re-run with `--allow-provisioning-updates` or set it via `sidekick configure`.
- **Defaults not applied**: Config is loaded from the current working directory; use `--path` to point at the project root containing `.sidekick/config.json`.

