import ArgumentParser
import Foundation

extension Sidekick {
  struct Archive: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Archive the app for device or macOS"
    )

    @Option(name: .customLong("path"), help: "Path to project directory")
    var path: String?

    @Option(name: .customLong("workspace"), help: "Path to .xcworkspace file")
    var workspace: String?

    @Option(name: .customLong("project"), help: "Path to .xcodeproj file")
    var project: String?

    @Option(name: .customLong("scheme"), help: "Archive scheme name")
    var scheme: String?

    @Option(name: .customLong("configuration"), help: "Build configuration (Debug/Release)")
    var configuration: String?

    @Option(name: .customLong("platform"), help: "Platform: ios-device, macos")
    var platform: Platform?

    @Option(name: .customLong("output"), help: "Directory or .xcarchive path for output")
    var output: String?

    @Option(name: .customLong("derived-data"), help: "Derived data path")
    var derivedData: String?

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

    @Flag(name: .customLong("clean"), help: "Clean before archiving")
    var clean: Bool = false

    func run() throws {
      if let path {
        let expandedPath = NSString(string: path).expandingTildeInPath
        print("📂 Changing to project directory: \(expandedPath)")
        guard FileManager.default.changeCurrentDirectoryPath(expandedPath) else {
          print("❌ Failed to change directory to: \(expandedPath)")
          throw ExitCode.failure
        }
      }

      print("⚙️  Loading configuration...")
      let config = loadConfigIfAvailable()
      if config != nil {
        print("   ✓ Found .sidekick/config.json")
      } else {
        print("   ⚠️  No config file found, using defaults")
      }

      let archiveScheme = scheme ?? config?.scheme ?? "clavis"
      let archiveConfig = configuration ?? config?.configuration ?? "Release"
      let archivePlatform = platform ?? config?.platform ?? .iosDevice
      let resolvedAllowProvisioning = allowProvisioningUpdates || (config?.allowProvisioningUpdates ?? false)
      let archivePath = try resolveArchivePath(
        output: output ?? config?.archiveOutputPath,
        scheme: archiveScheme
      )

      guard archivePlatform != .iosSim else {
        print("❌ Archive does not support ios-sim. Use ios-device or macos.")
        throw ExitCode.failure
      }

      print("\n📦 Preparing archive...")
      print("   Scheme: \(archiveScheme)")
      print("   Configuration: \(archiveConfig)")
      print("   Platform: \(archivePlatform.rawValue)")
      if let ws = workspace ?? config?.workspace {
        print("   Workspace: \(ws)")
      } else if let proj = project ?? config?.project {
        print("   Project: \(proj)")
      }
      if let resolvedDerivedData = derivedData ?? config?.derivedDataPath {
        print("   Derived Data: \(resolvedDerivedData)")
      }
      if resolvedAllowProvisioning {
        print("   Provisioning updates: Enabled")
      }
      if clean {
        print("   Clean archive: Yes")
      }
      print("   Output: \(archivePath)")

      let args = buildArchiveArgs(
        workspace: workspace ?? config?.workspace,
        project: project ?? config?.project,
        scheme: archiveScheme,
        configuration: archiveConfig,
        platform: archivePlatform,
        archivePath: archivePath,
        derivedData: derivedData ?? config?.derivedDataPath,
        allowProvisioningUpdates: resolvedAllowProvisioning,
        clean: clean
      )

      let result: ProcessResult
      if verbose {
        print("\n🔎 Streaming xcodebuild output...")
        result = try runProcessStreaming(executable: "/usr/bin/xcodebuild", arguments: args)
      } else {
        result = try withSpinner(message: "Archiving") {
          try runProcess(executable: "/usr/bin/xcodebuild", arguments: args)
        }
      }

      if result.exitCode != 0 {
        print("❌ Archive failed")
        let errors = extractBuildErrors(from: result.stdout + result.stderr)
        if !errors.isEmpty {
          print("\nErrors:")
          errors.forEach { print("  \($0)") }
        }
        throw ExitCode(result.exitCode)
      }

      print("\n✅ Archive created at: \(archivePath)")
    }
  }
}

private func resolveArchivePath(output: String?, scheme: String) throws -> String {
  let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
  let defaultDir = URL(fileURLWithPath: ".sidekick/archives", isDirectory: true)
  let defaultName = "\(scheme)-\(timestamp).xcarchive"

  if let output {
    let expanded = NSString(string: output).expandingTildeInPath
    let outputURL = URL(fileURLWithPath: expanded)
    if outputURL.pathExtension == "xcarchive" {
      try ensureDirectoryExists(outputURL.deletingLastPathComponent())
      return outputURL.path
    }

    try ensureDirectoryExists(outputURL)
    return outputURL.appendingPathComponent(defaultName).path
  }

  try ensureDirectoryExists(defaultDir)
  return defaultDir.appendingPathComponent(defaultName).path
}

private func ensureDirectoryExists(_ url: URL) throws {
  let fileManager = FileManager.default
  if fileManager.fileExists(atPath: url.path) {
    return
  }
  try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
}

private func buildArchiveArgs(
  workspace: String?,
  project: String?,
  scheme: String,
  configuration: String,
  platform: Platform,
  archivePath: String,
  derivedData: String?,
  allowProvisioningUpdates: Bool,
  clean: Bool
) -> [String] {
  var args: [String] = []

  if let workspace {
    args.append(contentsOf: ["-workspace", workspace])
  } else if let project {
    args.append(contentsOf: ["-project", project])
  }

  args.append(contentsOf: ["-scheme", scheme])
  args.append(contentsOf: ["-configuration", configuration])

  if let derivedData {
    args.append(contentsOf: ["-derivedDataPath", derivedData])
  }

  if allowProvisioningUpdates {
    args.append("-allowProvisioningUpdates")
  }

  switch platform {
  case .iosDevice:
    args.append(contentsOf: ["-sdk", "iphoneos"])
    args.append(contentsOf: ["-destination", "generic/platform=iOS"])
  case .macos:
    args.append(contentsOf: ["-sdk", "macosx"])
    args.append(contentsOf: ["-destination", "platform=macOS"])
  case .iosSim:
    break
  }

  if clean {
    args.append("clean")
  }

  args.append(contentsOf: ["archive", "-archivePath", archivePath])
  return args
}
