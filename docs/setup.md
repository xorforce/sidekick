# sidekick configure

Configure Sidekick defaults for a project.

## Quick usage

```bash
# From project root
sidekick configure --init

# From elsewhere
sidekick configure --init --path /path/to/MyApp

# Skip prompts, pick first detected options
sidekick configure --init --non-interactive

# Add a named config profile
sidekick config add <name>

# Edit a named config profile
sidekick config edit <name>
```

## Flags

- `--path <dir>`: Directory to scan for `.xcworkspace` or `.xcodeproj` (defaults to current).
- `--init`: Initialize a default config for this project.
- `--set <name>`: Set the default config name (copies it to `.sidekick/config.json`).
- `--non-interactive`: Auto-select the first detected workspace/project, scheme, configuration, and platform.
- `--allow-provisioning-updates`: Save a default to allow Xcode provisioning updates.
- `--archive-output <path>`: Default archive directory or `.xcarchive` path.

## What it does

1) Scans up to 3 levels deep for `.xcworkspace` and `.xcodeproj` (prefers workspaces).  
2) Lists schemes and build configurations via `xcodebuild -list`.  
3) Prompts (or auto-selects) scheme, configuration, and platform (`ios-sim`, `ios-device`, `macos`).  
4) If platform is `ios-sim`, optionally prompts for a **default simulator** (saved for future run/test commands).  
5) If platform is `ios-device`, optionally prompts for a **default device**, but only if a device is connected.  
6) Writes the named config to `.sidekick/configs/<name>.json` and sets `.sidekick/config.json` as the default.

## Command hooks

If `hooks.<command>.pre` or `hooks.<command>.post` are set in `.sidekick/config.json`, they run before/after that command (build/run/archive/test).

You can also set a default test plan using `testPlanPath` (name or `.xctestplan` path), which `sidekick test` will use unless overridden with `--test-plan`.

## One-time setup job

If `setupJob.pre` or `setupJob.post` is set in `.sidekick/config.json`, those commands run once when `sidekick setup` is invoked. After they run, `setupJobCompleted` is stored to prevent re-running.

```json
{
  "testPlanPath": "./Tests/MyApp.xctestplan",
  "hooks": {
    "build": {
      "pre": { "command": "bash", "args": ["./scripts/hook-echo.sh"] },
      "post": { "command": "bash", "args": ["./scripts/hook-echo.sh"] }
    },
    "test": {
      "pre": { "command": "bash", "args": ["./scripts/hook-echo.sh"] }
    }
  },
  "setupJob": {
    "pre": { "command": "bash", "args": ["./scripts/hook-echo.sh"] },
    "post": { "command": "bash", "args": ["./scripts/hook-echo.sh"] }
  }
}
```

## Run the setup job

```bash
# From project root
sidekick setup

# From elsewhere
sidekick setup --path /path/to/MyApp
```

## Best practices

- Run from the project root, or pass `--path` to avoid guessing.
- Prefer `.xcworkspace` when using CocoaPods/SwiftPM aggregates; otherwise `.xcodeproj` is fine.
- Keep scheme shared in Xcode so `xcodebuild -list` can see it.
- After changes to schemes/configs, re-run `sidekick configure --init` or `sidekick config edit` to refresh defaults.

## Do / Don't

- Do commit `.sidekick/config.json` only if it's meant to be team-wide; otherwise, leave it local.
- Do commit `.sidekick/configs/<name>.json` only if it's meant to be shared.
- Do verify `scheme` and `configuration` match CI expectations.
- Don't rely on `--non-interactive` if you have multiple similar schemes; pick explicitly.

## Troubleshooting

- **No projects found**: ensure the path is correct and contains `.xcworkspace` or `.xcodeproj`.
- **No schemes listed**: mark the scheme as shared in Xcode (`Manage Schemes > Shared`).
- **Defaults not applied in build**: the config is read from the current working directory; run `sidekick build` from the same root (or override with flags).
