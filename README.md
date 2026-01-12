# Sidekick

A quirky CLI for building, running, and testing iOS/macOS apps.

## Development

```bash
# Build the Swift package
swift build

# Run the CLI (shows help)
swift run sidekick --help

# Run tests (none yet, but wired up)
swift test
```

## Usage

```bash
# Build for iOS Simulator
swift run sidekick build --workspace MyApp.xcworkspace --scheme MyApp --platform ios-sim

# Build for iOS device
swift run sidekick build --project MyApp.xcodeproj --scheme MyApp --platform ios-device

# Build for macOS
swift run sidekick build --project MyMacApp.xcodeproj --scheme MyMacApp --platform macos

# Clean then build a Release config
swift run sidekick build --workspace MyApp.xcworkspace --scheme MyApp --configuration Release --clean
```

## License

MIT
