import ArgumentParser
import Foundation

@main
struct Sidekick: ParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "sidekick",
    abstract: "A quirky CLI for building, running, and testing iOS/macOS apps",
    version: "0.1.0",
    subcommands: [Build.self, Init.self]
  )
}

extension Sidekick {
  struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Build for simulator, device, or macOS"
    )

    @Option(name: .customLong("profile"), help: "Use named profile (future use)")
    var profile: String?

    @Option(name: .customLong("workspace"), help: "Path to .xcworkspace file")
    var workspace: String?

    @Option(name: .customLong("project"), help: "Path to .xcodeproj file")
    var project: String?

    @Option(name: .customLong("scheme"), help: "Build scheme name")
    var scheme: String?

    @Option(name: .customLong("configuration"), help: "Build configuration (Debug/Release)")
    var configuration: String?

    @Option(name: .customLong("platform"), help: "Platform: ios-sim, ios-device, macos")
    var platform: Platform?

    @Flag(name: .customLong("clean"), help: "Clean before building")
    var clean: Bool = false

    func run() throws {
      let config = loadConfigIfAvailable()

      let options = BuildOptions(
        profile: profile,
        workspace: workspace ?? config?.workspace,
        project: project ?? config?.project,
        scheme: scheme ?? config?.scheme ?? "clavis",
        configuration: configuration ?? config?.configuration ?? "Debug",
        platform: platform ?? config?.platform,
        clean: clean
      )

      let logPaths = try createLogPaths()

      do {
        let result = try runXcodebuild(options: options)
        print("✅ Build succeeded")

        let rawLog = result.stdout + result.stderr
        try rawLog.write(to: logPaths.rawLogURL, atomically: true, encoding: .utf8)

        let prettyLog = runXcprettyIfAvailable(rawLog: rawLog)
        let prettyToSave = prettyLog ?? rawLog
        try prettyToSave.write(to: logPaths.prettyLogURL, atomically: true, encoding: .utf8)

        print("\nLogs saved to:")
        print("  Raw: \(logPaths.rawLogURL.path)")
        if prettyLog != nil {
          print("  Pretty: \(logPaths.prettyLogURL.path)")
        } else {
          print("  Pretty (fallback to raw): \(logPaths.prettyLogURL.path)")
        }
      } catch {
        print("❌ Build failed")

        if let buildError = error as? BuildError {
          try? buildError.rawLog?.write(to: logPaths.rawLogURL, atomically: true, encoding: .utf8)
          try? buildError.prettyLog?.write(
            to: logPaths.prettyLogURL,
            atomically: true,
            encoding: .utf8
          )

          if !buildError.errors.isEmpty {
            print("\nErrors:")
            buildError.errors.forEach { print("  \($0)") }
          }

          print("\nSee full log: \(logPaths.rawLogURL.path)")
          throw ExitCode(buildError.exitCode)
        }

        print("Error: \(error.localizedDescription)")
        throw ExitCode.failure
      }
    }
  }
}

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

      let scheme: String
      if schemes.isEmpty {
        print("No schemes detected. Enter scheme name: ", terminator: "")
        scheme = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if scheme.isEmpty {
          print("Scheme is required.")
          throw ExitCode(1)
        }
      } else {
        scheme = chooseOption(
          prompt: "Select scheme",
          options: schemes,
          nonInteractive: nonInteractive
        ) ?? schemes.first!
      }

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

      let config = SidekickConfig(
        workspace: project.workspacePath,
        project: project.projectPath,
        scheme: scheme,
        configuration: configuration,
        platform: platform
      )

      try saveConfig(config, root: root)
      print("""
Saved sidekick config:
  Workspace: \(config.workspace ?? "-")
  Project: \(config.project ?? "-")
  Scheme: \(config.scheme ?? "-")
  Configuration: \(config.configuration ?? "-")
  Platform: \(config.platform?.rawValue ?? "-")
  Path: \(configFilePath(root: root).path)
""")
    }
  }
}

// MARK: - Build plumbing

private struct SidekickConfig: Codable {
  var workspace: String?
  var project: String?
  var scheme: String?
  var configuration: String?
  var platform: Platform?
  var derivedDataPath: String?
}

private struct ProjectEntry {
  enum Kind {
    case workspace
    case project
  }

  let url: URL
  let kind: Kind

  var displayName: String {
    url.lastPathComponent
  }

  var workspacePath: String? {
    kind == .workspace ? url.path : nil
  }

  var projectPath: String? {
    kind == .project ? url.path : nil
  }
}

private struct BuildOptions {
  let profile: String?
  let workspace: String?
  let project: String?
  let scheme: String
  let configuration: String
  let platform: Platform?
  let clean: Bool
}

private struct BuildResult {
  let exitCode: Int32
  let stdout: String
  let stderr: String
  let prettyLog: String?
}

private struct LogPaths {
  let baseDir: URL
  let rawLogURL: URL
  let prettyLogURL: URL
}

private enum BuildError: Error {
  case failed(exitCode: Int32, rawLog: String, prettyLog: String?, errors: [String])

  var exitCode: Int32 {
    switch self {
    case .failed(let exitCode, _, _, _):
      return exitCode
    }
  }

  var rawLog: String? {
    switch self {
    case .failed(_, let rawLog, _, _):
      return rawLog
    }
  }

  var prettyLog: String? {
    switch self {
    case .failed(_, _, let prettyLog, _):
      return prettyLog
    }
  }

  var errors: [String] {
    switch self {
    case .failed(_, _, _, let errors):
      return errors
    }
  }
}

// MARK: - Init helpers

private func configFilePath(root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> URL {
  return root.appendingPathComponent(".sidekick/config.json")
}

private func loadConfigIfAvailable(root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> SidekickConfig? {
  let path = configFilePath(root: root)
  guard FileManager.default.fileExists(atPath: path.path) else {
    return nil
  }

  do {
    let data = try Data(contentsOf: path)
    return try JSONDecoder().decode(SidekickConfig.self, from: data)
  } catch {
    print("Warning: failed to load config at \(path.path): \(error)")
    return nil
  }
}

private func saveConfig(_ config: SidekickConfig, root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws {
  let path = configFilePath(root: root)
  try FileManager.default.createDirectory(
    at: path.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let data = try encoder.encode(config)
  try data.write(to: path, options: .atomic)
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
  guard entries.count > 1, !nonInteractive else {
    return entries.first!
  }

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

private func chooseOption(prompt: String, options: [String], nonInteractive: Bool) -> String? {
  guard !options.isEmpty else { return nil }
  guard options.count > 1, !nonInteractive else {
    return options.first
  }

  print("\(prompt):")
  for (index, option) in options.enumerated() {
    print("  [\(index + 1)] \(option)")
  }
  print("Enter choice (1-\(options.count)) [1]: ", terminator: "")
  if let input = readLine(),
     let choice = Int(input.trimmingCharacters(in: .whitespaces)),
     choice >= 1, choice <= options.count {
    return options[choice - 1]
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
  guard process.terminationStatus == 0 else {
    return []
  }

  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  guard let output = String(data: data, encoding: .utf8) else {
    return []
  }

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

private func runXcodebuild(options: BuildOptions) throws -> BuildResult {
  if let xcprettyPath = resolveXcprettyPath() {
    return try runXcodebuildStreaming(options: options, xcprettyPath: xcprettyPath)
  }

  return try runXcodebuildRaw(options: options)
}

private func runXcodebuildRaw(options: BuildOptions) throws -> BuildResult {
  let args = buildArguments(options: options)

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
  process.arguments = args

  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe

  var stdoutData = Data()
  var stderrData = Data()

  stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if !data.isEmpty {
      stdoutData.append(data)
    }
  }

  stderrPipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if !data.isEmpty {
      stderrData.append(data)
    }
  }

  do {
    try process.run()
  } catch {
    throw BuildError.failed(exitCode: 1, rawLog: "Failed to spawn xcodebuild: \(error)", prettyLog: nil, errors: ["Failed to spawn xcodebuild: \(error)"])
  }

  process.waitUntilExit()

  stdoutPipe.fileHandleForReading.readabilityHandler = nil
  stderrPipe.fileHandleForReading.readabilityHandler = nil

  stdoutData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
  stderrData.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

  let exitCode = process.terminationStatus
  let stdoutString = String(decoding: stdoutData, as: UTF8.self)
  let stderrString = String(decoding: stderrData, as: UTF8.self)

  if exitCode != 0 {
    let rawLog = stdoutString + stderrString
    let prettyLog = runXcprettyIfAvailable(rawLog: rawLog)
    let errors = extractErrors(from: prettyLog ?? rawLog)
    throw BuildError.failed(
      exitCode: exitCode,
      rawLog: rawLog,
      prettyLog: prettyLog,
      errors: errors
    )
  }

  return BuildResult(exitCode: exitCode, stdout: stdoutString, stderr: stderrString, prettyLog: nil)
}

private func runXcodebuildStreaming(options: BuildOptions, xcprettyPath: String) throws -> BuildResult {
  let args = buildArguments(options: options)

  let xcodebuild = Process()
  xcodebuild.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
  xcodebuild.arguments = args

  let xcpretty = Process()
  xcpretty.executableURL = URL(fileURLWithPath: xcprettyPath)

  let xcodeStdout = Pipe()
  let xcodeStderr = Pipe()
  let xcprettyIn = Pipe()
  let xcprettyOut = Pipe()
  let xcprettyErr = Pipe()

  xcodebuild.standardOutput = xcodeStdout
  xcodebuild.standardError = xcodeStderr
  xcpretty.standardInput = xcprettyIn
  xcpretty.standardOutput = xcprettyOut
  xcpretty.standardError = xcprettyErr

  var rawData = Data()
  var stdoutData = Data()
  var stderrData = Data()
  var prettyData = Data()
  var prettyErrorData = Data()

  xcodeStdout.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if !data.isEmpty {
      rawData.append(data)
      stdoutData.append(data)
      xcprettyIn.fileHandleForWriting.write(data)
    }
  }

  xcodeStderr.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if !data.isEmpty {
      rawData.append(data)
      stderrData.append(data)
      xcprettyIn.fileHandleForWriting.write(data)
    }
  }

  xcprettyOut.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if !data.isEmpty {
      prettyData.append(data)
      FileHandle.standardOutput.write(data)
    }
  }

  xcprettyErr.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if !data.isEmpty {
      prettyErrorData.append(data)
      FileHandle.standardOutput.write(data)
    }
  }

  do {
    try xcpretty.run()
    try xcodebuild.run()
  } catch {
    throw BuildError.failed(
      exitCode: 1,
      rawLog: "Failed to spawn xcodebuild/xcpretty: \(error)",
      prettyLog: nil,
      errors: ["Failed to spawn xcodebuild/xcpretty: \(error)"]
    )
  }

  xcodebuild.waitUntilExit()
  xcprettyIn.fileHandleForWriting.closeFile()
  xcpretty.waitUntilExit()

  xcodeStdout.fileHandleForReading.readabilityHandler = nil
  xcodeStderr.fileHandleForReading.readabilityHandler = nil
  xcprettyOut.fileHandleForReading.readabilityHandler = nil
  xcprettyErr.fileHandleForReading.readabilityHandler = nil

  rawData.append(xcodeStdout.fileHandleForReading.readDataToEndOfFile())
  rawData.append(xcodeStderr.fileHandleForReading.readDataToEndOfFile())
  stdoutData.append(xcodeStdout.fileHandleForReading.readDataToEndOfFile())
  stderrData.append(xcodeStderr.fileHandleForReading.readDataToEndOfFile())
  prettyData.append(xcprettyOut.fileHandleForReading.readDataToEndOfFile())
  prettyErrorData.append(xcprettyErr.fileHandleForReading.readDataToEndOfFile())

  let exitCode = xcodebuild.terminationStatus
  let stdoutString = String(decoding: stdoutData, as: UTF8.self)
  let stderrString = String(decoding: stderrData, as: UTF8.self)
  let rawLogString = String(decoding: rawData, as: UTF8.self)
  let prettyLogString = String(decoding: prettyData + prettyErrorData, as: UTF8.self)

  if exitCode != 0 {
    let errors = extractErrors(from: prettyLogString.isEmpty ? rawLogString : prettyLogString)
    throw BuildError.failed(
      exitCode: exitCode,
      rawLog: rawLogString,
      prettyLog: prettyLogString.isEmpty ? nil : prettyLogString,
      errors: errors
    )
  }

  return BuildResult(
    exitCode: exitCode,
    stdout: stdoutString,
    stderr: stderrString,
    prettyLog: prettyLogString.isEmpty ? nil : prettyLogString
  )
}

private func buildArguments(options: BuildOptions) -> [String] {
  var args: [String] = []

  if let workspace = options.workspace {
    args.append(contentsOf: ["-workspace", workspace])
  } else if let project = options.project {
    args.append(contentsOf: ["-project", project])
  }

  args.append(contentsOf: ["-scheme", options.scheme])
  args.append(contentsOf: ["-configuration", options.configuration])

  switch options.platform {
  case .iosSim:
    args.append(contentsOf: ["-sdk", "iphonesimulator"])
    args.append(contentsOf: ["-destination", "generic/platform=iOS Simulator"])
  case .iosDevice:
    args.append(contentsOf: ["-sdk", "iphoneos"])
    args.append(contentsOf: ["-destination", "generic/platform=iOS"])
  case .macos:
    args.append(contentsOf: ["-sdk", "macosx"])
    args.append(contentsOf: ["-destination", "platform=macOS"])
  case .none:
    break
  }

  if options.clean {
    args.append("clean")
  }

  args.append("build")
  return args
}

private func createLogPaths() throws -> LogPaths {
  let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
  let baseDir = URL(fileURLWithPath: ".sidekick/logs/build-\(timestamp)", isDirectory: true)
  try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

  let rawLogURL = baseDir.appendingPathComponent("raw.log")
  let prettyLogURL = baseDir.appendingPathComponent("pretty.log")

  return LogPaths(baseDir: baseDir, rawLogURL: rawLogURL, prettyLogURL: prettyLogURL)
}

private func extractErrors(from output: String) -> [String] {
  let pattern = #"error:\s*(.+)"#
  guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
    return []
  }

  let range = NSRange(location: 0, length: output.utf16.count)
  let matches = regex.matches(in: output, options: [], range: range)

  var errors: [String] = []
  for match in matches {
    if let range = Range(match.range(at: 1), in: output) {
      let message = output[range].trimmingCharacters(in: .whitespacesAndNewlines)
      let normalized = message.lowercased().hasPrefix("error:") ? String(message.dropFirst(6)).trimmingCharacters(in: .whitespaces) : message
      let full = "error: \(normalized)"
      if !errors.contains(full) {
        errors.append(full)
      }
    }
  }
  return errors
}

private func runXcprettyIfAvailable(rawLog: String) -> String? {
  guard let executablePath = resolveXcprettyPath() else {
    return nil
  }

  let process = Process()
  process.executableURL = URL(fileURLWithPath: executablePath)

  let inputPipe = Pipe()
  let outputPipe = Pipe()
  process.standardInput = inputPipe
  process.standardOutput = outputPipe
  process.standardError = Pipe()

  do {
    try process.run()
  } catch {
    return nil
  }

  if let data = rawLog.data(using: .utf8) {
    inputPipe.fileHandleForWriting.write(data)
  }
  inputPipe.fileHandleForWriting.closeFile()

  process.waitUntilExit()

  guard process.terminationStatus == 0 else {
    return nil
  }

  let prettyData = outputPipe.fileHandleForReading.readDataToEndOfFile()
  return String(data: prettyData, encoding: .utf8)
}

private func resolveXcprettyPath() -> String? {
  let fileManager = FileManager.default
  let candidates = [
    "/opt/homebrew/bin/xcpretty",
    "/usr/local/bin/xcpretty",
    "/usr/bin/xcpretty"
  ]

  if let found = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
    return found
  }

  // Try xcrun lookup to respect active toolchain
  let xcrunProcess = Process()
  xcrunProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
  xcrunProcess.arguments = ["--find", "xcpretty"]

  let xcrunOut = Pipe()
  xcrunProcess.standardOutput = xcrunOut
  xcrunProcess.standardError = Pipe()

  do {
    try xcrunProcess.run()
    xcrunProcess.waitUntilExit()
    if xcrunProcess.terminationStatus == 0 {
      let data = xcrunOut.fileHandleForReading.readDataToEndOfFile()
      if let path = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !path.isEmpty,
        fileManager.isExecutableFile(atPath: path) {
        return path
      }
    }
  } catch {
    // Ignore and fall back to PATH lookup
  }

  let whichProcess = Process()
  whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  whichProcess.arguments = ["which", "xcpretty"]

  let outputPipe = Pipe()
  whichProcess.standardOutput = outputPipe
  whichProcess.standardError = Pipe()

  do {
    try whichProcess.run()
  } catch {
    return nil
  }

  whichProcess.waitUntilExit()
  guard whichProcess.terminationStatus == 0 else {
    return nil
  }

  let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
  guard var path = String(data: data, encoding: .utf8) else {
    return nil
  }

  path = path.trimmingCharacters(in: .whitespacesAndNewlines)
  return path.isEmpty ? nil : path
}

// MARK: - Platform

enum Platform: String, ExpressibleByArgument, CaseIterable, Codable {
  case iosSim = "ios-sim"
  case iosDevice = "ios-device"
  case macos = "macos"
}
