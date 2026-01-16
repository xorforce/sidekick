import ArgumentParser
import Foundation

extension Sidekick {
  struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Build, install, and launch the app on device or simulator"
    )

    @Option(name: .customLong("path"), help: "Path to project directory")
    var path: String?

    @Option(name: .customLong("workspace"), help: "Path to .xcworkspace file")
    var workspace: String?

    @Option(name: .customLong("project"), help: "Path to .xcodeproj file")
    var project: String?

    @Option(name: .customLong("scheme"), help: "Build scheme name")
    var scheme: String?

    @Option(name: .customLong("configuration"), help: "Build configuration (Debug/Release)")
    var configuration: String?

    @Option(name: .customLong("config"), help: "Path to Sidekick config file")
    var configPath: String?

    @Flag(name: .customLong("clean"), help: "Clean before building")
    var clean: Bool = false

    @Flag(name: .customLong("simulator"), help: "Force run on simulator even if device is available")
    var forceSimulator: Bool = false

    @Flag(
      name: .customLong("allow-provisioning-updates"),
      help: "Allow Xcode to update provisioning profiles automatically"
    )
    var allowProvisioningUpdates: Bool = false

    @Flag(
      name: .customLong("verbose"),
      help: "Stream full xcodebuild output"
    )
    var verbose: Bool = false

    func run() throws {
      // Change to project directory if specified
      if let path = path {
        let expandedPath = NSString(string: path).expandingTildeInPath
        print("📂 Changing to project directory: \(expandedPath)")
        guard FileManager.default.changeCurrentDirectoryPath(expandedPath) else {
          print("❌ Failed to change directory to: \(expandedPath)")
          throw ExitCode.failure
        }
      }

      print("⚙️  Loading configuration...")
      let config = loadConfigIfAvailable(configPath: configPath)
      if config != nil {
        if let configPath {
          print("   ✓ Found config at \(configPath)")
        } else {
          print("   ✓ Found .sidekick/config.json")
        }
      } else {
        if let configPath {
          print("   ⚠️  No config file found at \(configPath), using defaults")
        } else {
          print("   ⚠️  No config file found, using defaults")
        }
      }
      try runHookIfNeeded(config: config, command: .run, phase: .pre)

      print("\n🔍 Determining run target...")
      let target = try determineRunTarget(config: config, forceSimulator: forceSimulator)
      print("   ✓ Selected: \(target.displayName)")

      if allowProvisioningUpdates || (config?.allowProvisioningUpdates ?? false) {
        print("   ✓ Provisioning updates enabled")
      }

      // Build the app
      print("\n🔨 Starting build phase...")
      _ = try buildApp(config: config, target: target)

      // Find the app bundle
      print("\n📦 Locating app bundle...")
      let appPath = try findAppBundle(config: config, target: target)
      print("   ✓ Found: \(appPath)")

      // Install and launch
      print("\n🚀 Starting deployment phase...")
      try installAndLaunch(appPath: appPath, target: target, config: config)

      try runHookIfNeeded(config: config, command: .run, phase: .post)
      print("\n✅ Launch command completed (see output above for PID / errors).")
    }

    private func buildApp(config: SidekickConfig?, target: RunTarget) throws -> BuildOutput {
      let platform: Platform = target.isDevice ? .iosDevice : .iosSim
      let resolvedAllowProvisioning = allowProvisioningUpdates || (config?.allowProvisioningUpdates ?? false)

      let buildScheme = scheme ?? config?.scheme ?? "clavis"
      let buildConfig = configuration ?? config?.configuration ?? "Debug"
      let buildWorkspace = workspace ?? config?.workspace
      let buildProject = project ?? config?.project

      print("   Scheme: \(buildScheme)")
      print("   Configuration: \(buildConfig)")
      print("   Platform: \(platform.rawValue)")
      if let ws = buildWorkspace {
        print("   Workspace: \(ws)")
      } else if let proj = buildProject {
        print("   Project: \(proj)")
      }
      print("   Target: \(target.name) (\(target.udid))")
      if clean {
        print("   Clean build: Yes")
      }
      if resolvedAllowProvisioning {
        print("   Provisioning updates: Enabled")
      }

      let args = buildXcodebuildArgs(
        workspace: buildWorkspace,
        project: buildProject,
        scheme: buildScheme,
        configuration: buildConfig,
        target: target,
        allowProvisioningUpdates: resolvedAllowProvisioning,
        clean: clean
      )

      let result: ProcessResult
      if verbose {
        print("🔎 Streaming xcodebuild output...")
        result = try runProcessStreaming(executable: "/usr/bin/xcodebuild", arguments: args)
      } else {
        result = try withSpinner(message: "Building..") {
          try runProcess(executable: "/usr/bin/xcodebuild", arguments: args)
        }
      }

      if result.exitCode != 0 {
        print("   ✗ Build failed")
        let errors = extractBuildErrors(from: result.stdout + result.stderr)
        if !errors.isEmpty {
          print("\n   Errors:")
          errors.forEach { print("     \($0)") }
        }
        throw ExitCode(result.exitCode)
      }

      print("   ✓ Build succeeded")
      return BuildOutput(stdout: result.stdout, stderr: result.stderr)
    }

    private func buildXcodebuildArgs(
      workspace: String?,
      project: String?,
      scheme: String,
      configuration: String,
      target: RunTarget,
      allowProvisioningUpdates: Bool,
      clean: Bool
    ) -> [String] {
      var args: [String] = []

      if let workspace = workspace {
        args.append(contentsOf: ["-workspace", workspace])
      } else if let project = project {
        args.append(contentsOf: ["-project", project])
      }

      args.append(contentsOf: ["-scheme", scheme])
      args.append(contentsOf: ["-configuration", configuration])

      if target.isDevice {
        args.append(contentsOf: ["-sdk", "iphoneos"])
        args.append(contentsOf: ["-destination", "platform=iOS,id=\(target.udid)"])
      } else {
        args.append(contentsOf: ["-sdk", "iphonesimulator"])
        args.append(contentsOf: ["-destination", "platform=iOS Simulator,id=\(target.udid)"])
      }

      if clean {
        args.append("clean")
      }

      if allowProvisioningUpdates {
        args.append("-allowProvisioningUpdates")
      }

      args.append("build")
      return args
    }

    private func findAppBundle(config: SidekickConfig?, target: RunTarget) throws -> String {
      let buildScheme = scheme ?? config?.scheme ?? "clavis"
      let buildConfig = configuration ?? config?.configuration ?? "Debug"

      // Use xcodebuild -showBuildSettings to find the built products directory
      var args: [String] = []

      if let ws = workspace ?? config?.workspace {
        args.append(contentsOf: ["-workspace", ws])
      } else if let proj = project ?? config?.project {
        args.append(contentsOf: ["-project", proj])
      }

      args.append(contentsOf: ["-scheme", buildScheme])
      args.append(contentsOf: ["-configuration", buildConfig])

      if target.isDevice {
        args.append(contentsOf: ["-sdk", "iphoneos"])
      } else {
        args.append(contentsOf: ["-sdk", "iphonesimulator"])
      }

      args.append("-showBuildSettings")

      let result = try withSpinner(message: "Querying build settings") {
        try runProcess(executable: "/usr/bin/xcodebuild", arguments: args)
      }

      guard result.exitCode == 0 else {
        throw RunError.failedToGetBuildSettings(result.stderr)
      }

      let output = result.stdout
      guard let builtProductsDir = extractBuildSetting("BUILT_PRODUCTS_DIR", from: output),
            let productName = extractBuildSetting("FULL_PRODUCT_NAME", from: output) else {
        throw RunError.missingBuildSettings
      }

      print("   Build products dir: \(builtProductsDir)")
      print("   Product name: \(productName)")

      let appPath = (builtProductsDir as NSString).appendingPathComponent(productName)

      guard FileManager.default.fileExists(atPath: appPath) else {
        throw RunError.appBundleNotFound(appPath)
      }

      return appPath
    }

    private func extractBuildSetting(_ key: String, from output: String) -> String? {
      let pattern = "\\s+\(key) = (.+)"
      guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
            let match = regex.firstMatch(
              in: output,
              options: [],
              range: NSRange(location: 0, length: output.utf16.count)
            ),
            let range = Range(match.range(at: 1), in: output) else {
        return nil
      }
      return String(output[range]).trimmingCharacters(in: .whitespaces)
    }

    private func installAndLaunch(appPath: String, target: RunTarget, config: SidekickConfig?) throws {
      let bundleId = try extractBundleIdentifier(from: appPath)
      print("   Bundle ID: \(bundleId)")

      if target.isDevice {
        print("   Deploying to device: \(target.name)")
        try installOnDevice(appPath: appPath, deviceUDID: target.udid)
        try launchOnDevice(bundleId: bundleId, deviceUDID: target.udid)
      } else {
        print("   Deploying to simulator: \(target.name)")
        try bootSimulatorIfNeeded(udid: target.udid)
        try openSimulatorApp(udid: target.udid)
        try installOnSimulator(appPath: appPath, simulatorUDID: target.udid)
        try launchOnSimulator(bundleId: bundleId, simulatorUDID: target.udid)
      }
    }

    private func extractBundleIdentifier(from appPath: String) throws -> String {
      let plistPath = (appPath as NSString).appendingPathComponent("Info.plist")

      guard FileManager.default.fileExists(atPath: plistPath) else {
        throw RunError.infoPlistNotFound(plistPath)
      }

      let result = try runProcess(
        executable: "/usr/bin/plutil",
        arguments: ["-extract", "CFBundleIdentifier", "raw", plistPath]
      )

      guard result.exitCode == 0 else {
        throw RunError.failedToExtractBundleId(result.stderr)
      }

      return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Simulator Operations

    private func bootSimulatorIfNeeded(udid: String) throws {
      let result = try withSpinner(message: "Checking simulator state") {
        try runProcess(
          executable: "/usr/bin/xcrun",
          arguments: ["simctl", "list", "-j", "devices"]
        )
      }

      guard result.exitCode == 0,
            let data = result.stdout.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devices = json["devices"] as? [String: [[String: Any]]] else {
        print("   ⚠️  Could not check simulator state")
        return
      }

      for (_, deviceList) in devices {
        if let device = deviceList.first(where: { ($0["udid"] as? String) == udid }),
           let state = device["state"] as? String {
          if state == "Booted" {
            print("   ✓ Simulator already booted")
          } else {
            _ = try withSpinner(message: "Booting simulator") {
              try runProcess(
                executable: "/usr/bin/xcrun",
                arguments: ["simctl", "boot", udid]
              )
            }
            Thread.sleep(forTimeInterval: 2)
            print("   ✓ Simulator booted")
          }
          break
        }
      }
    }

    private func openSimulatorApp(udid: String) throws {
      _ = try withSpinner(message: "Opening Simulator app") {
        try runProcess(
          executable: "/usr/bin/open",
          arguments: ["-a", "Simulator", "--args", "-CurrentDeviceUDID", udid]
        )
      }
    }

    private func installOnSimulator(appPath: String, simulatorUDID: String) throws {
      let result = try withSpinner(message: "Installing app on simulator") {
        try runProcess(
          executable: "/usr/bin/xcrun",
          arguments: ["simctl", "install", simulatorUDID, appPath]
        )
      }

      guard result.exitCode == 0 else {
        throw RunError.installFailed(result.stderr)
      }
      print("   ✓ App installed")
    }

    private func launchOnSimulator(bundleId: String, simulatorUDID: String) throws {
      let result = try withSpinner(message: "Launching app") {
        try runProcess(
          executable: "/usr/bin/xcrun",
          arguments: ["simctl", "launch", simulatorUDID, bundleId]
        )
      }

      guard result.exitCode == 0 else {
        throw RunError.launchFailed(result.stderr)
      }
      let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      if !out.isEmpty {
        print("   simctl: \(out)")
      }
      if let pid = parseSimctlLaunchPID(out, bundleId: bundleId) {
        print("   ✓ App launched (pid \(pid))")
      } else {
        print("   ⚠️  Launch reported success, but no PID was found in output")
      }
    }

    // MARK: - Device Operations

    private func installOnDevice(appPath: String, deviceUDID: String) throws {
      let result = try withSpinner(message: "Installing app on device") {
        try runProcess(
          executable: "/usr/bin/xcrun",
          arguments: ["devicectl", "device", "install", "app", "--device", deviceUDID, appPath]
        )
      }

      guard result.exitCode == 0 else {
        throw RunError.installFailed(result.stderr)
      }
      print("   ✓ App installed")
    }

    private func launchOnDevice(bundleId: String, deviceUDID: String) throws {
      let result = try withSpinner(message: "Launching app") {
        try runProcess(
          executable: "/usr/bin/xcrun",
          arguments: ["devicectl", "device", "process", "launch", "--device", deviceUDID, bundleId]
        )
      }

      guard result.exitCode == 0 else {
        throw RunError.launchFailed(result.stderr)
      }
      let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
      if !out.isEmpty {
        print("   devicectl: \(out)")
      }
      print("   ✓ Launch command succeeded")
    }
  }
}

private func parseSimctlLaunchPID(_ output: String, bundleId: String) -> Int? {
  // Typical output is: "<bundleId>: <pid>"
  let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  let tokens = trimmed.split(separator: " ").map(String.init)
  guard let last = tokens.last else { return nil }
  let pidString = last.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
  return Int(pidString)
}
