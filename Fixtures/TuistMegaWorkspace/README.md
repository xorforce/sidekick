# Tuist Mega Workspace Fixture

This fixture is a large Tuist-generated iOS workspace for Sidekick integration testing.

- 5 app targets
- 18 framework targets
- 5 unit test targets
- 23+ auto-generated shared schemes from buildable targets
- 4 build configurations on every target: `Debug`, `Staging`, `Release`, `Benchmark`
- 2 third-party packages installed through Tuist: Kingfisher, SnapKit

Generate it from this directory with:

```bash
tuist install
tuist generate
```

Validate the generated workspace with:

```bash
xcodebuild -list -workspace SidekickMegaWorkspace.xcworkspace
```
