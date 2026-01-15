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
      let existingConfig = loadConfigIfAvailable(root: root)
      let projects = withSpinner(message: "Detecting projects") {
        detectProjects(in: root)
      }

      guard !projects.isEmpty else {
        print("No .xcworkspace or .xcodeproj found under \(root.path).")
        throw ExitCode(1)
      }

      let project = chooseProject(from: projects, nonInteractive: nonInteractive)
      let schemes = withSpinner(message: "Listing schemes") {
        listSchemes(for: project)
      }
      let configurations = withSpinner(message: "Listing configurations") {
        listConfigurations(for: project)
      }

      let scheme = try chooseScheme(schemes: schemes, nonInteractive: nonInteractive)
      let configuration = chooseOption(
        prompt: "Select configuration",
        options: configurations.isEmpty ? ["Debug", "Release"] : configurations,
        nonInteractive: nonInteractive
      ) ?? "Debug"

      let platformOptions = Platform.allCases.map { $0.rawValue }
      let platformRaw = chooseOption(
        prompt: "Select platform",
        options: platformOptions,
        nonInteractive: nonInteractive
      ) ?? Platform.iosSim.rawValue
      let platform = Platform(rawValue: platformRaw)

      var config = SidekickConfig(
        workspace: project.workspacePath,
        project: project.projectPath,
        scheme: scheme,
        configuration: configuration,
        platform: platform,
        allowProvisioningUpdates: allowProvisioningUpdates,
        archiveOutputPath: archiveOutput,
        hooks: existingConfig?.hooks,
        setupJob: existingConfig?.setupJob,
        setupJobCompleted: existingConfig?.setupJobCompleted ?? false
      )

      if platform == .iosSim {
        applyDefaultSimulator(to: &config, nonInteractive: nonInteractive)
      }

      if platform == .iosDevice {
        applyDefaultDeviceIfAny(to: &config, nonInteractive: nonInteractive)
      }

      try saveConfig(config, root: root)

      print("""
Saved sidekick config:
  Workspace: \(config.workspace ?? "-")
  Project: \(config.project ?? "-")
  Scheme: \(config.scheme ?? "-")
  Configuration: \(config.configuration ?? "-")
  Platform: \(config.platform?.rawValue ?? "-")
  Provisioning updates: \(config.allowProvisioningUpdates ? "Enabled" : "Disabled")
  Archive output: \(config.archiveOutputPath ?? "-")
  Default simulator: \(formatDefault(name: config.simulatorName, id: config.simulatorUDID))
  Default device: \(formatDefault(name: config.deviceName, id: config.deviceUDID))
  Path: \(configFilePath(root: root).path)
""")
    }
  }
}

private func formatDefault(name: String?, id: String?) -> String {
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

private func chooseScheme(schemes: [String], nonInteractive: Bool) throws -> String {
  if schemes.isEmpty {
    print("No schemes detected. Enter scheme name: ", terminator: "")
    let scheme = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if scheme.isEmpty {
      print("Scheme is required.")
      throw ExitCode(1)
    }
    return scheme
  }

  return chooseOption(prompt: "Select scheme", options: schemes, nonInteractive: nonInteractive) ?? schemes.first!
}

private func formatRuntimeForDisplay(_ runtimeKey: String) -> String {
  var s = runtimeKey
  s = s.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
  
  if s.hasPrefix("iOS-") {
    return "iOS \(String(s.dropFirst(4)).replacingOccurrences(of: "-", with: "."))"
  } else if s.hasPrefix("tvOS-") {
    return "tvOS \(String(s.dropFirst(5)).replacingOccurrences(of: "-", with: "."))"
  } else if s.hasPrefix("watchOS-") {
    return "watchOS \(String(s.dropFirst(8)).replacingOccurrences(of: "-", with: "."))"
  } else if s.hasPrefix("visionOS-") {
    return "visionOS \(String(s.dropFirst(9)).replacingOccurrences(of: "-", with: "."))"
  } else if s.hasPrefix("macOS-") {
    return "macOS \(String(s.dropFirst(6)).replacingOccurrences(of: "-", with: "."))"
  }
  
  var fallback = s
  fallback = fallback.replacingOccurrences(of: "iOS-", with: "iOS ")
  fallback = fallback.replacingOccurrences(of: "tvOS-", with: "tvOS ")
  fallback = fallback.replacingOccurrences(of: "watchOS-", with: "watchOS ")
  fallback = fallback.replacingOccurrences(of: "visionOS-", with: "visionOS ")
  fallback = fallback.replacingOccurrences(of: "-", with: ".")
  return fallback
}

private func applyDefaultSimulator(to config: inout SidekickConfig, nonInteractive: Bool) {
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

    if let chosen = chooseOption(prompt: "Select default simulator (used for run/test)", options: options, nonInteractive: nonInteractive, allowSkip: true) {
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

private func applyDefaultDeviceIfAny(to config: inout SidekickConfig, nonInteractive: Bool) {
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
      
      if let chosen = chooseOption(
        prompt: "Select default device (used for run/test)",
        options: deviceOptions,
        nonInteractive: nonInteractive,
        allowSkip: true
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
    
    let simulatorPrompt = devices.isEmpty
      ? "Select default simulator (used for run/test)"
      : "Select fallback simulator (used when device is not connected)"
    
    if let chosen = chooseOption(
      prompt: simulatorPrompt,
      options: simulatorOptions,
      nonInteractive: nonInteractive,
      allowSkip: !devices.isEmpty  // Only allow skip if device was selected
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

private struct ProjectEntry {
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

private func detectProjects(in root: URL) -> [ProjectEntry] {
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

private func chooseProject(from entries: [ProjectEntry], nonInteractive: Bool) -> ProjectEntry {
  guard entries.count > 1, !nonInteractive else { return entries.first! }

  let options = entries.map { $0.displayName }
  if let selected = InteractiveSelection.select(
    prompt: "Select workspace/project",
    options: options
  ) {
    if let index = options.firstIndex(of: selected) {
      return entries[index]
    }
  }

  return entries.first!
}

private func chooseOption(
  prompt: String,
  options: [String],
  nonInteractive: Bool,
  allowSkip: Bool = false
) -> String? {
  guard !options.isEmpty else { return nil }
  guard options.count > 1, !nonInteractive else { return options.first }

  return InteractiveSelection.select(
    prompt: prompt,
    options: options,
    allowSkip: allowSkip
  )
}

private func listSchemes(for entry: ProjectEntry) -> [String] {
  let args: [String]
  switch entry.kind {
  case .workspace:
    args = ["-list", "-workspace", entry.url.path]
  case .project:
    args = ["-list", "-project", entry.url.path]
  }

  return parseListSection(command: "/usr/bin/xcodebuild", arguments: args, section: "Schemes")
}

private func listConfigurations(for entry: ProjectEntry) -> [String] {
  let args: [String]
  switch entry.kind {
  case .workspace:
    args = ["-list", "-workspace", entry.url.path]
  case .project:
    args = ["-list", "-project", entry.url.path]
  }

  return parseListSection(command: "/usr/bin/xcodebuild", arguments: args, section: "Build Configurations")
}

private func parseListSection(command: String, arguments: [String], section: String) -> [String] {
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


private func formatDeviceDisplay(_ device: PhysicalDevice) -> String {
  let name = device.name ?? "Unknown"
  let platform = formatPlatform(device.platform ?? "unknown")
  let osVersion = formatOSVersion(device.osVersion ?? "unknown")
  let id = device.identifier ?? "-"
  
  // Format: "Name - Platform Version - ID" or "Name - Platform - ID" if no version
  if osVersion.isEmpty {
    return "\(name) - \(platform) - \(id)"
  } else {
    return "\(name) - \(platform) \(osVersion) - \(id)"
  }
}

private func formatPlatform(_ platform: String) -> String {
  if platform.contains("iphoneos") || platform.contains("iphone") {
    return "iOS"
  } else if platform.contains("ipados") || platform.contains("ipad") {
    return "iPadOS"
  } else if platform.contains("macos") || platform.contains("mac") {
    return "macOS"
  } else if platform.contains("watchos") || platform.contains("watch") {
    return "watchOS"
  } else if platform.contains("tvos") || platform.contains("tv") {
    return "tvOS"
  } else if platform.contains("visionos") || platform.contains("vision") {
    return "visionOS"
  }
  return platform
}

private func formatOSVersion(_ osVersion: String) -> String {
  // Return the actual OS version, or empty string if unknown
  if osVersion == "unknown" || osVersion.isEmpty {
    return ""
  }
  return osVersion
}
