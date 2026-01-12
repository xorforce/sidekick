import ArgumentParser
import Foundation

@main
struct Sidekick: ParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "sidekick",
    abstract: "A quirky CLI for building, running, and testing iOS/macOS apps",
    version: "0.1.0",
    subcommands: [Build.self]
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
      let options = BuildOptions(
        profile: profile,
        workspace: workspace,
        project: project,
        scheme: scheme ?? "clavis",
        configuration: configuration ?? "Debug",
        platform: platform,
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

// MARK: - Build plumbing

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

enum Platform: String, ExpressibleByArgument {
  case iosSim = "ios-sim"
  case iosDevice = "ios-device"
  case macos = "macos"
}
