import ArgumentParser
import Foundation

extension Sidekick {
  struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Initialize sidekick defaults for this project"
    )

    @Option(name: .customLong("path"), help: "Project root to scan (defaults to current directory)")
    var path: String?

    @Flag(name: .customLong("non-interactive"), help: "Use first detected options without prompts")
    var nonInteractive: Bool = false

    func run() throws {
      let root = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)
      let projects = detectProjects(in: root)

      guard !projects.isEmpty else {
        print("No .xcworkspace or .xcodeproj found under \(root.path).")
        throw ExitCode(1)
      }

      let project = chooseProject(from: projects, nonInteractive: nonInteractive)
      let schemes = listSchemes(for: project)
      let configurations = listConfigurations(for: project)

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
        platform: platform
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

private func applyDefaultSimulator(to config: inout SidekickConfig, nonInteractive: Bool) {
  do {
    let groups = try fetchSimulators()
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
      let state = device.state ?? "unknown"
      return "\(device.name) — \(runtime) — \(state) — \(device.udid)"
    }

    if let chosen = chooseOption(prompt: "Select default simulator (used for run/test)", options: options, nonInteractive: nonInteractive, allowSkip: true) {
      if let match = flattened.first(where: { "\($0.1.name) — \($0.0) — \($0.1.state ?? "unknown") — \($0.1.udid)" == chosen }) {
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
    let devices = try fetchConnectedPhysicalDevices()
    guard !devices.isEmpty else {
      print("No connected devices detected; skipping default device.")
      return
    }

    let options = devices.map { device in
      let name = device.name ?? "Unknown"
      let platform = device.platform ?? "unknown"
      let os = device.osVersion ?? "unknown"
      let id = device.identifier ?? ""
      return "\(name) — \(platform) \(os) — \(id)"
    }

    guard let chosen = chooseOption(
      prompt: "Select default device (used for run/test)",
      options: options,
      nonInteractive: nonInteractive,
      allowSkip: true
    ) else {
      return
    }

    guard let match = devices.first(where: { device in
      let name = device.name ?? "Unknown"
      let platform = device.platform ?? "unknown"
      let os = device.osVersion ?? "unknown"
      let id = device.identifier ?? ""
      return "\(name) — \(platform) \(os) — \(id)" == chosen
    }) else {
      return
    }

    if let id = match.identifier, !id.isEmpty {
      config.deviceName = match.name
      config.deviceUDID = id
    }
  } catch {
    print("Warning: failed to list devices (\(error)); skipping default device.")
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

  print("Select workspace/project:")
  for (index, entry) in entries.enumerated() {
    print("  [\(index + 1)] \(entry.displayName)")
  }
  print("Enter choice (1-\(entries.count)) [1]: ", terminator: "")

  if let input = readLine(),
     let choice = Int(input.trimmingCharacters(in: .whitespaces)),
     choice >= 1, choice <= entries.count {
    return entries[choice - 1]
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

  print("\(prompt):")
  if allowSkip {
    print("  [0] Skip")
  }
  for (index, option) in options.enumerated() {
    print("  [\(index + 1)] \(option)")
  }

  let rangeLabel = allowSkip ? "0-\(options.count)" : "1-\(options.count)"
  print("Enter choice (\(rangeLabel)) [1]: ", terminator: "")

  if let input = readLine() {
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    if allowSkip, trimmed == "0" {
      return nil
    }
    if let choice = Int(trimmed), choice >= 1, choice <= options.count {
      return options[choice - 1]
    }
  }

  return options.first
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
    if trimmed.hasPrefix(section + ":") {
      inSection = true
      continue
    }
    if inSection {
      if trimmed.hasSuffix(":") { break }
      values.append(trimmed)
    }
  }
  return values
}

