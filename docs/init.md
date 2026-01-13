# sidekick init

Initialize Sidekick defaults for a project.

## Quick usage

```bash
# From project root
sidekick init

# From elsewhere
sidekick init --path /path/to/MyApp

# Skip prompts, pick first detected options
sidekick init --non-interactive
```

## Flags

- `--path <dir>`: Directory to scan for `.xcworkspace` or `.xcodeproj` (defaults to current).
- `--non-interactive`: Auto-select the first detected workspace/project, scheme, configuration, and platform.

## What it does

1) Scans up to 3 levels deep for `.xcworkspace` and `.xcodeproj` (prefers workspaces).  
2) Lists schemes and build configurations via `xcodebuild -list`.  
3) Prompts (or auto-selects) scheme, configuration, and platform (`ios-sim`, `ios-device`, `macos`).  
4) Lists available test plans via `xcodebuild -showTestPlans` (if any) and lets you pick one (or `None`).  
5) Writes `.sidekick/config.json` in the target directory with the chosen defaults.

## Best practices

- Run from the project root, or pass `--path` to avoid guessing.
- Prefer `.xcworkspace` when using CocoaPods/SwiftPM aggregates; otherwise `.xcodeproj` is fine.
- Keep scheme shared in Xcode so `xcodebuild -list` can see it.
- After changes to schemes/configs, re-run `sidekick init` to refresh defaults.

## Do / Don't

- Do commit `.sidekick/config.json` only if it’s meant to be team-wide; otherwise, leave it local.
- Do verify `scheme` and `configuration` match CI expectations.
- Don’t rely on `--non-interactive` if you have multiple similar schemes; pick explicitly.

## Troubleshooting

- **No projects found**: ensure the path is correct and contains `.xcworkspace` or `.xcodeproj`.
- **No schemes listed**: mark the scheme as shared in Xcode (`Manage Schemes > Shared`).
- **Defaults not applied in build**: the config is read from the current working directory; run `sidekick build` from the same root (or override with flags).
