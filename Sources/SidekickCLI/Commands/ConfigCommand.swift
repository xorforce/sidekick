import ArgumentParser
import Foundation

extension Sidekick {
  struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "config",
      abstract: "Manage sidekick config profiles",
      subcommands: [Add.self, Edit.self]
    )
  }
}

extension Sidekick.Config {
  struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Add a new config profile"
    )

    @Argument(help: "Name for the config profile")
    var name: String

    @Option(name: .customLong("path"), help: "Project root to scan (defaults to current directory)")
    var path: String?

    @Flag(name: .customLong("non-interactive"), help: "Use first detected options without prompts")
    var nonInteractive: Bool = false

    @Flag(
      name: .customLong("allow-provisioning-updates"),
      help: "Allow Xcode to update provisioning profiles automatically"
    )
    var allowProvisioningUpdates: Bool = false

    @Option(
      name: .customLong("archive-output"),
      help: "Default archive directory or .xcarchive path"
    )
    var archiveOutput: String?

    func run() throws {
      let root = resolveRoot(path)
      let normalizedName = normalizeConfigName(name)
      guard !normalizedName.isEmpty else {
        print("❌ Config name cannot be empty.")
        throw ExitCode(1)
      }
      let targetPath = namedConfigPath(name: normalizedName, root: root)
      if FileManager.default.fileExists(atPath: targetPath.path) {
        print("❌ Config '\(normalizedName)' already exists at \(targetPath.path)")
        throw ExitCode(1)
      }

      let existingConfig = loadConfigIfAvailable(root: root)
      let config = try buildSidekickConfig(
        root: root,
        existingConfig: existingConfig,
        nonInteractive: nonInteractive,
        allowProvisioningUpdates: allowProvisioningUpdates,
        archiveOutput: archiveOutput,
        selectedConfig: nil
      )

      try saveNamedConfig(config, name: normalizedName, root: root)
      printConfigSummary(config: config, name: normalizedName, root: root)
      print("Use 'sidekick configure --set \(normalizedName)' to set it as default.")
    }
  }

  struct Edit: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Edit an existing config profile"
    )

    @Argument(help: "Name of the config profile to edit")
    var name: String?

    @Option(name: .customLong("path"), help: "Project root to scan (defaults to current directory)")
    var path: String?

    @Flag(name: .customLong("non-interactive"), help: "Use first detected options without prompts")
    var nonInteractive: Bool = false

    @Flag(
      name: .customLong("allow-provisioning-updates"),
      help: "Enable provisioning updates for this config"
    )
    var allowProvisioningUpdates: Bool = false

    @Option(
      name: .customLong("archive-output"),
      help: "Default archive directory or .xcarchive path"
    )
    var archiveOutput: String?

    func run() throws {
      let root = resolveRoot(path)
      let resolvedName = try resolveConfigName(name, root: root, nonInteractive: nonInteractive)
      guard let existingConfig = loadNamedConfig(name: resolvedName, root: root) else {
        print("❌ Config '\(resolvedName)' not found.")
        throw ExitCode(1)
      }

      let resolvedAllowProvisioning = allowProvisioningUpdates
        ? true
        : existingConfig.allowProvisioningUpdates
      let resolvedArchiveOutput = archiveOutput ?? existingConfig.archiveOutputPath

      let config = try buildSidekickConfig(
        root: root,
        existingConfig: existingConfig,
        nonInteractive: nonInteractive,
        allowProvisioningUpdates: resolvedAllowProvisioning,
        archiveOutput: resolvedArchiveOutput,
        selectedConfig: existingConfig
      )

      try saveNamedConfig(config, name: resolvedName, root: root)
      if readDefaultConfigName(root: root) == resolvedName {
        try setDefaultConfig(name: resolvedName, root: root)
      }

      printConfigSummary(config: config, name: resolvedName, root: root)
    }
  }
}

private func resolveRoot(_ path: String?) -> URL {
  let rootPath = path ?? FileManager.default.currentDirectoryPath
  let expanded = NSString(string: rootPath).expandingTildeInPath
  return URL(fileURLWithPath: expanded)
}

private func normalizeConfigName(_ name: String) -> String {
  name.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func resolveConfigName(_ name: String?, root: URL, nonInteractive: Bool) throws -> String {
  if let name {
    let normalized = normalizeConfigName(name)
    if !normalized.isEmpty {
      return normalized
    }
  }

  let names = listConfigNames(root: root)
  guard !names.isEmpty else {
    print("❌ No configs found. Use 'sidekick config add <name>' first.")
    throw ExitCode(1)
  }

  let defaultName = readDefaultConfigName(root: root)
  guard names.count > 1, !nonInteractive else {
    return defaultName ?? names.first!
  }

  let displayOptions = names.map { name in
    if name == defaultName {
      return "(selected) \(name)"
    }
    return name
  }

  if let selected = InteractiveSelection.select(
    prompt: "Select config to edit",
    options: displayOptions
  ), let index = displayOptions.firstIndex(of: selected) {
    return names[index]
  }

  return defaultName ?? names.first!
}

private func printConfigSummary(config: SidekickConfig, name: String, root: URL) {
  print("""
Saved sidekick config:
  Name: \(name)
  Workspace: \(config.workspace ?? "-")
  Project: \(config.project ?? "-")
  Scheme: \(config.scheme ?? "-")
  Configuration: \(config.configuration ?? "-")
  Platform: \(config.platform?.rawValue ?? "-")
  Provisioning updates: \(config.allowProvisioningUpdates ? "Enabled" : "Disabled")
  Archive output: \(config.archiveOutputPath ?? "-")
  Test plan: \(config.testPlanPath ?? "-")
  Default simulator: \(formatDefault(name: config.simulatorName, id: config.simulatorUDID))
  Default device: \(formatDefault(name: config.deviceName, id: config.deviceUDID))
  Config path: \(namedConfigPath(name: name, root: root).path)
""")
}
