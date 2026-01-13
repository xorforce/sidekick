import ArgumentParser
import Foundation

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
        clean: clean,
        config: config
      )

      let logPaths = try createLogPaths()

      do {
        // Determine which destination will be used
        let destination = determineBuildDestination(options: options)
        if let dest = destination {
          let destType = dest.type == "device" ? "device" : "simulator"
          print("Building for \(destType): \(dest.name) (\(dest.id))")
        }
        
        // Only show spinner if xcpretty is not available (raw output mode)
        let hasXcpretty = resolveXcprettyPath() != nil
        let result: BuildResult
        if hasXcpretty {
          // Streaming output, no spinner
          result = try runXcodebuild(options: options)
        } else {
          // Raw output, show spinner
          result = try withSpinner(message: "Building") {
            try runXcodebuild(options: options)
          }
        }
        print("✅ Build succeeded")
        
        // Add destination info to logs
        var logHeader = "Build completed successfully\n"
        logHeader += "Scheme: \(options.scheme)\n"
        logHeader += "Configuration: \(options.configuration)\n"
        if let dest = destination {
          logHeader += "Target: \(dest.type) - \(dest.name) (\(dest.id))\n"
        } else if let platform = options.platform {
          logHeader += "Platform: \(platform.rawValue)\n"
        }
        logHeader += "\n"

        let rawLog = logHeader + result.stdout + result.stderr
        try rawLog.write(to: logPaths.rawLogURL, atomically: true, encoding: .utf8)

        let prettyLog = runXcprettyIfAvailable(rawLog: rawLog)
        let prettyToSave = (prettyLog ?? rawLog)
        let prettyWithHeader = logHeader + prettyToSave
        try prettyWithHeader.write(to: logPaths.prettyLogURL, atomically: true, encoding: .utf8)

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
          // Add destination info to error logs
          let buildDestination = determineBuildDestination(options: options)
          var logHeader = "Build failed\n"
          logHeader += "Scheme: \(options.scheme)\n"
          logHeader += "Configuration: \(options.configuration)\n"
          if let dest = buildDestination {
            logHeader += "Target: \(dest.type) - \(dest.name) (\(dest.id))\n"
          } else if let platform = options.platform {
            logHeader += "Platform: \(platform.rawValue)\n"
          }
          logHeader += "\n"
          
          if let rawLog = buildError.rawLog {
            try? (logHeader + rawLog).write(to: logPaths.rawLogURL, atomically: true, encoding: .utf8)
          }
          if let prettyLog = buildError.prettyLog {
            try? (logHeader + prettyLog).write(to: logPaths.prettyLogURL, atomically: true, encoding: .utf8)
          }

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
  let config: SidekickConfig?
}

private struct BuildResult {
  let exitCode: Int32
  let stdout: String
  let stderr: String
}

private struct LogPaths {
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

  let result = try runProcess(executable: "/usr/bin/xcodebuild", arguments: args)
  if result.exitCode != 0 {
    let rawLog = result.stdout + result.stderr
    let prettyLog = runXcprettyIfAvailable(rawLog: rawLog)
    let errors = extractErrors(from: prettyLog ?? rawLog)
    throw BuildError.failed(exitCode: result.exitCode, rawLog: rawLog, prettyLog: prettyLog, errors: errors)
  }

  return BuildResult(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)
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

  let rawData = DataBox()
  let stdoutData = DataBox()
  let stderrData = DataBox()
  let prettyData = DataBox()
  let prettyErrorData = DataBox()

  hookStreamingPipe(
    pipe: xcodeStdout,
    rawData: rawData,
    capturedData: stdoutData,
    forwardTo: xcprettyIn
  )
  hookStreamingPipe(
    pipe: xcodeStderr,
    rawData: rawData,
    capturedData: stderrData,
    forwardTo: xcprettyIn
  )
  hookOutputPipeToStdout(pipe: xcprettyOut, capturedData: prettyData)
  hookOutputPipeToStdout(pipe: xcprettyErr, capturedData: prettyErrorData)

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

  unhookPipe(xcodeStdout)
  unhookPipe(xcodeStderr)
  unhookPipe(xcprettyOut)
  unhookPipe(xcprettyErr)

  rawData.value.append(xcodeStdout.fileHandleForReading.readDataToEndOfFile())
  rawData.value.append(xcodeStderr.fileHandleForReading.readDataToEndOfFile())
  stdoutData.value.append(xcodeStdout.fileHandleForReading.readDataToEndOfFile())
  stderrData.value.append(xcodeStderr.fileHandleForReading.readDataToEndOfFile())
  prettyData.value.append(xcprettyOut.fileHandleForReading.readDataToEndOfFile())
  prettyErrorData.value.append(xcprettyErr.fileHandleForReading.readDataToEndOfFile())

  let exitCode = xcodebuild.terminationStatus
  let stdoutString = String(decoding: stdoutData.value, as: UTF8.self)
  let stderrString = String(decoding: stderrData.value, as: UTF8.self)
  let rawLogString = String(decoding: rawData.value, as: UTF8.self)
  let prettyLogString = String(decoding: prettyData.value + prettyErrorData.value, as: UTF8.self)

  if exitCode != 0 {
    let errors = extractErrors(from: prettyLogString.isEmpty ? rawLogString : prettyLogString)
    throw BuildError.failed(
      exitCode: exitCode,
      rawLog: rawLogString,
      prettyLog: prettyLogString.isEmpty ? nil : prettyLogString,
      errors: errors
    )
  }

  return BuildResult(exitCode: exitCode, stdout: stdoutString, stderr: stderrString)
}

private final class DataBox {
  var value = Data()
}

private func hookStreamingPipe(
  pipe: Pipe,
  rawData: DataBox,
  capturedData: DataBox,
  forwardTo: Pipe
) {
  pipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if data.isEmpty { return }
    rawData.value.append(data)
    capturedData.value.append(data)
    forwardTo.fileHandleForWriting.write(data)
  }
}

private func hookOutputPipeToStdout(pipe: Pipe, capturedData: DataBox) {
  pipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if data.isEmpty { return }
    capturedData.value.append(data)
    FileHandle.standardOutput.write(data)
  }
}

private func unhookPipe(_ pipe: Pipe) {
  pipe.fileHandleForReading.readabilityHandler = nil
}

private struct BuildDestination {
  let type: String // "device" or "simulator"
  let name: String
  let id: String
  let destinationArg: String
}

private func determineBuildDestination(options: BuildOptions) -> BuildDestination? {
  guard options.platform == .iosDevice || options.platform == .iosSim else {
    return nil
  }
  
  // For iOS device platform, try device first, then simulator
  if options.platform == .iosDevice {
    // Check if device is available and configured
    if let deviceUDID = options.config?.deviceUDID, !deviceUDID.isEmpty,
       let deviceName = options.config?.deviceName {
      // Verify device is still connected
      if let devices = try? fetchConnectedPhysicalDevices(),
         devices.contains(where: { $0.identifier == deviceUDID }) {
        return BuildDestination(
          type: "device",
          name: deviceName,
          id: deviceUDID,
          destinationArg: "id=\(deviceUDID)"
        )
      }
    }
    
    // Fall back to simulator if device not available
    if let simulatorUDID = options.config?.simulatorUDID, !simulatorUDID.isEmpty,
       let simulatorName = options.config?.simulatorName {
      return BuildDestination(
        type: "simulator",
        name: simulatorName,
        id: simulatorUDID,
        destinationArg: "id=\(simulatorUDID)"
      )
    }
  }
  
  // For iOS simulator platform, use simulator if configured
  if options.platform == .iosSim {
    if let simulatorUDID = options.config?.simulatorUDID, !simulatorUDID.isEmpty,
       let simulatorName = options.config?.simulatorName {
      return BuildDestination(
        type: "simulator",
        name: simulatorName,
        id: simulatorUDID,
        destinationArg: "id=\(simulatorUDID)"
      )
    }
  }
  
  return nil
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

  let destination = determineBuildDestination(options: options)
  
  switch options.platform {
  case .iosSim:
    args.append(contentsOf: ["-sdk", "iphonesimulator"])
    if let dest = destination {
      args.append(contentsOf: ["-destination", "platform=iOS Simulator,\(dest.destinationArg)"])
    } else {
      args.append(contentsOf: ["-destination", "generic/platform=iOS Simulator"])
    }
  case .iosDevice:
    if let dest = destination {
      if dest.type == "device" {
        args.append(contentsOf: ["-sdk", "iphoneos"])
        args.append(contentsOf: ["-destination", "platform=iOS,\(dest.destinationArg)"])
      } else {
        // Fallback to simulator - switch SDK
        args.append(contentsOf: ["-sdk", "iphonesimulator"])
        args.append(contentsOf: ["-destination", "platform=iOS Simulator,\(dest.destinationArg)"])
      }
    } else {
      args.append(contentsOf: ["-sdk", "iphoneos"])
      args.append(contentsOf: ["-destination", "generic/platform=iOS"])
    }
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

  return LogPaths(
    rawLogURL: baseDir.appendingPathComponent("raw.log"),
    prettyLogURL: baseDir.appendingPathComponent("pretty.log")
  )
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
    guard let range = Range(match.range(at: 1), in: output) else { continue }
    let message = output[range].trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = message.lowercased().hasPrefix("error:")
      ? String(message.dropFirst(6)).trimmingCharacters(in: .whitespaces)
      : message
    let full = "error: \(normalized)"
    if !errors.contains(full) { errors.append(full) }
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
  guard process.terminationStatus == 0 else { return nil }

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

  let xcrun = try? runProcess(executable: "/usr/bin/xcrun", arguments: ["--find", "xcpretty"])
  if let xcrun, xcrun.exitCode == 0 {
    let path = xcrun.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if !path.isEmpty, fileManager.isExecutableFile(atPath: path) {
      return path
    }
  }

  let which = try? runProcess(executable: "/usr/bin/env", arguments: ["which", "xcpretty"])
  if let which, which.exitCode == 0 {
    let path = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    return path.isEmpty ? nil : path
  }

  return nil
}

