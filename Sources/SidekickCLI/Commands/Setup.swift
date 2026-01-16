import ArgumentParser
import Foundation

extension Sidekick {
  struct Configure: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "configure",
      abstract: "Configure sidekick defaults for this project"
    )

    @Option(name: .customLong("path"), help: "Project root to scan (defaults to current directory)")
    var path: String?

    @Flag(name: .customLong("init"), help: "Initialize a default config for this project")
    var initialize: Bool = false

    @Option(name: .customLong("set"), help: "Set the default config name")
    var setDefault: String?

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
      let root = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)
      if let setDefault {
        do {
          try setDefaultConfig(name: setDefault, root: root)
          print("✅ Default config set to '\(setDefault)'")
          return
        } catch {
          print("❌ \(error.localizedDescription)")
          throw ExitCode(1)
        }
      }

      guard initialize else {
        print("❌ Missing action. Use 'sidekick configure --init' for setup or 'sidekick configure --set <name>'.")
        throw ExitCode(1)
      }

      try runInit(root: root)
    }

    private func runInit(root: URL) throws {
      let existingConfig = loadConfigIfAvailable(root: root)
      let config = try buildSidekickConfig(
        root: root,
        existingConfig: existingConfig,
        nonInteractive: nonInteractive,
        allowProvisioningUpdates: allowProvisioningUpdates,
        archiveOutput: archiveOutput,
        selectedConfig: nil
      )

      let defaultName = "default"
      try saveNamedConfig(config, name: defaultName, root: root)
      try setDefaultConfig(name: defaultName, root: root)

      print("""
Saved sidekick config:
  Name: \(defaultName)
  Workspace: \(config.workspace ?? "-")
  Project: \(config.project ?? "-")
  Scheme: \(config.scheme ?? "-")
  Configuration: \(config.configuration ?? "-")
  Platform: \(config.platform?.rawValue ?? "-")
  Provisioning updates: \(config.allowProvisioningUpdates ? "Enabled" : "Disabled")
  Archive output: \(config.archiveOutputPath ?? "-")
  Default simulator: \(formatDefault(name: config.simulatorName, id: config.simulatorUDID))
  Default device: \(formatDefault(name: config.deviceName, id: config.deviceUDID))
  Config path: \(namedConfigPath(name: defaultName, root: root).path)
  Default path: \(configFilePath(root: root).path)
""")
    }
  }
}

func formatDefault(name: String?, id: String?) -> String {
  switch (name?.trimmingCharacters(in: .whitespacesAndNewlines), id?.trimmingCharacters(in: .whitespacesAndNewlines)) {
  case (let name?, let id?) where !name.isEmpty && !id.isEmpty:
    return "\(name) (\(id))"
  case (let name?, _) where !name.isEmpty:
    return name
  case (_, let id?) where !id.isEmpty:
    return id
  default:
    return "-"
  }
}

func chooseScheme(schemes: [String], nonInteractive: Bool, selected: String? = nil) throws -> String {
  if schemes.isEmpty {
    print("No schemes detected. Enter scheme name: ", terminator: "")
    let scheme = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if scheme.isEmpty {
      print("Scheme is required.")
      throw ExitCode(1)
    }
    return scheme
  }

  return chooseOption(
    prompt: "Select scheme",
    options: schemes,
    nonInteractive: nonInteractive,
    selected: selected
  ) ?? schemes.first!
}

func applyDefaultSimulator(to config: inout SidekickConfig, nonInteractive: Bool) {
  do {
    let groups = try withSpinner(message: "Fetching simulators") {
      try fetchSimulators()
    }
    let flattened = groups.flatMap { group in
      group.devices.map { device in
        (group.runtime, device)
      }
    }

    guard !flattened.isEmpty else {
      print("No available simulators detected; skipping default simulator.")
      return
    }

    let options = flattened.map { (runtime, device) in
      let runtimeDisplay = formatRuntimeForDisplay(runtime)
      return "\(device.name) - \(runtimeDisplay)"
    }

    let selectedOption = flattened.first { (_, device) in
      device.name == config.simulatorName
    }.map { (runtime, device) in
      let runtimeDisplay = formatRuntimeForDisplay(runtime)
      return "\(device.name) - \(runtimeDisplay)"
    }

    if let chosen = chooseOption(
      prompt: "Select default simulator (used for run/test)",
      options: options,
      nonInteractive: nonInteractive,
      allowSkip: true,
      selected: selectedOption
    ) {
      if let match = flattened.first(where: { (runtime, device) in
        let runtimeDisplay = formatRuntimeForDisplay(runtime)
        return "\(device.name) - \(runtimeDisplay)" == chosen
      }) {
        config.simulatorName = match.1.name
        config.simulatorUDID = match.1.udid
      }
    }
  } catch {
    print("Warning: failed to list simulators (\(error)); skipping default simulator.")
  }
}

func applyDefaultDeviceIfAny(to config: inout SidekickConfig, nonInteractive: Bool) {
  do {
    let devices = try withSpinner(message: "Fetching devices") {
      try fetchConnectedPhysicalDevices()
    }
    
    // Always fetch simulators for fallback
    let groups = try withSpinner(message: "Fetching simulators") {
      try fetchSimulators()
    }
    let simulators = groups.flatMap { group in
      group.devices.map { device in (group.runtime, device) }
    }
    
    // If devices are available, let user select one
    if !devices.isEmpty {
      let deviceOptions = devices.map { formatDeviceDisplay($0) }
      let selectedDeviceOption = devices.first { $0.identifier == config.deviceUDID }.map {
        formatDeviceDisplay($0)
      }
      
      if let chosen = chooseOption(
        prompt: "Select default device (used for run/test)",
        options: deviceOptions,
        nonInteractive: nonInteractive,
        allowSkip: true,
        selected: selectedDeviceOption
      ) {
        if let match = devices.first(where: { formatDeviceDisplay($0) == chosen }) {
          if let id = match.identifier, !id.isEmpty {
            config.deviceName = match.name
            config.deviceUDID = id
          }
        }
      }
    } else {
      print("No connected devices detected.")
    }
    
    // Always ask for a fallback simulator (even if device was selected)
    guard !simulators.isEmpty else {
      if devices.isEmpty {
        print("No simulators available either; skipping default device/simulator.")
      }
      return
    }
    
    let simulatorOptions = simulators.map { (runtime, device) in
      let runtimeDisplay = formatRuntimeForDisplay(runtime)
      return "\(device.name) - \(runtimeDisplay)"
    }
    let selectedSimulatorOption = simulators.first { (_, device) in
      device.udid == config.simulatorUDID
    }.map { (runtime, device) in
      let runtimeDisplay = formatRuntimeForDisplay(runtime)
      return "\(device.name) - \(runtimeDisplay)"
    }
    
    let simulatorPrompt = devices.isEmpty
      ? "Select default simulator (used for run/test)"
      : "Select fallback simulator (used when device is not connected)"
    
    if let chosen = chooseOption(
      prompt: simulatorPrompt,
      options: simulatorOptions,
      nonInteractive: nonInteractive,
      allowSkip: !devices.isEmpty,  // Only allow skip if device was selected
      selected: selectedSimulatorOption
    ) {
      if let match = simulators.first(where: { (runtime, device) in
        let runtimeDisplay = formatRuntimeForDisplay(runtime)
        return "\(device.name) - \(runtimeDisplay)" == chosen
      }) {
        config.simulatorName = match.1.name
        config.simulatorUDID = match.1.udid
      }
    }
  } catch {
    print("Warning: failed to list devices/simulators (\(error)); skipping default device/simulator.")
  }
}

// MARK: - Project detection and xcodebuild -list parsing

struct ProjectEntry {
  enum Kind {
    case workspace
    case project
  }

  let url: URL
  let kind: Kind

  var displayName: String { url.lastPathComponent }
  var workspacePath: String? { kind == .workspace ? url.path : nil }
  var projectPath: String? { kind == .project ? url.path : nil }
}

func detectProjects(in root: URL) -> [ProjectEntry] {
  guard let enumerator = FileManager.default.enumerator(
    at: root,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
  ) else {
    return []
  }

  var results: [ProjectEntry] = []
  for case let url as URL in enumerator {
    let depth = url.pathComponents.count - root.pathComponents.count
    if depth > 3 {
      enumerator.skipDescendants()
      continue
    }

    switch url.pathExtension {
    case "xcworkspace":
      results.append(ProjectEntry(url: url, kind: .workspace))
    case "xcodeproj":
      results.append(ProjectEntry(url: url, kind: .project))
    default:
      break
    }
  }

  return results.sorted { lhs, rhs in
    if lhs.kind != rhs.kind {
      return lhs.kind == .workspace
    }
    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
  }
}

func chooseProject(
  from entries: [ProjectEntry],
  nonInteractive: Bool,
  selectedPath: String? = nil
) -> ProjectEntry {
  let selectedIndex = entries.firstIndex { $0.url.path == selectedPath }
  guard entries.count > 1, !nonInteractive else {
    return selectedIndex.map { entries[$0] } ?? entries.first!
  }

  let options = entries.map { $0.displayName }
  let displayOptions = options.enumerated().map { index, name in
    if index == selectedIndex {
      return "(selected) \(name)"
    }
    return name
  }
  if let selected = InteractiveSelection.select(
    prompt: "Select workspace/project",
    options: displayOptions
  ) {
    if let index = displayOptions.firstIndex(of: selected) {
      return entries[index]
    }
  }

  return entries.first!
}

func chooseOption(
  prompt: String,
  options: [String],
  nonInteractive: Bool,
  allowSkip: Bool = false,
  selected: String? = nil
) -> String? {
  guard !options.isEmpty else { return nil }
  guard options.count > 1, !nonInteractive else { return selected ?? options.first }

  let displayOptions = options.map { option in
    if option == selected {
      return "(selected) \(option)"
    }
    return option
  }
  if let chosen = InteractiveSelection.select(
    prompt: prompt,
    options: displayOptions,
    allowSkip: allowSkip
  ), let index = displayOptions.firstIndex(of: chosen) {
    return options[index]
  }

  return options.first
}

func listSchemes(for entry: ProjectEntry) -> [String] {
  let args: [String]
  switch entry.kind {
  case .workspace:
    args = ["-list", "-workspace", entry.url.path]
  case .project:
    args = ["-list", "-project", entry.url.path]
  }

  return parseListSection(command: "/usr/bin/xcodebuild", arguments: args, section: "Schemes")
}

func listConfigurations(for entry: ProjectEntry) -> [String] {
  let args: [String]
  switch entry.kind {
  case .workspace:
    args = ["-list", "-workspace", entry.url.path]
  case .project:
    args = ["-list", "-project", entry.url.path]
  }

  return parseListSection(command: "/usr/bin/xcodebuild", arguments: args, section: "Build Configurations")
}

func parseListSection(command: String, arguments: [String], section: String) -> [String] {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: command)
  process.arguments = arguments
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = Pipe()

  do {
    try process.run()
  } catch {
    return []
  }

  process.waitUntilExit()
  guard process.terminationStatus == 0 else { return [] }

  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  guard let output = String(data: data, encoding: .utf8) else { return [] }

  var values: [String] = []
  var inSection = false
  for line in output.split(separator: "\n") {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { continue }
    
    // Check if this is the section we're looking for
    if trimmed.hasPrefix(section + ":") {
      inSection = true
      continue
    }
    
    // If we're in the section, collect values
    if inSection {
      // Stop if we hit another section header (line ending with ":")
      if trimmed.hasSuffix(":") && trimmed != section + ":" {
        break
      }
      // Only add non-empty lines that aren't section headers
      if !trimmed.hasSuffix(":") {
        values.append(trimmed)
      }
    }
  }
  return values
}


