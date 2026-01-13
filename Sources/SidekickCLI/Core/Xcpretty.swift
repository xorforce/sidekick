import Foundation

func resolveXcprettyPath() -> String? {
  if let path = findXcprettyInCommonLocations() { return path }
  if let path = findXcprettyViaXcrun() { return path }
  return findXcprettyViaWhich()
}

func runXcprettyIfAvailable(rawLog: String) -> String? {
  guard let executablePath = resolveXcprettyPath() else { return nil }
  return runXcpretty(rawLog: rawLog, executablePath: executablePath)
}

private func findXcprettyInCommonLocations() -> String? {
  let candidates = [
    "/opt/homebrew/bin/xcpretty",
    "/usr/local/bin/xcpretty",
    "/usr/bin/xcpretty",
  ]
  return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
}

private func findXcprettyViaXcrun() -> String? {
  let out = runProcess(executablePath: "/usr/bin/xcrun", arguments: ["--find", "xcpretty"])
  guard out.exitCode == 0 else { return nil }
  let path = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !path.isEmpty else { return nil }
  return FileManager.default.isExecutableFile(atPath: path) ? path : nil
}

private func findXcprettyViaWhich() -> String? {
  let out = runProcess(executablePath: "/usr/bin/env", arguments: ["which", "xcpretty"])
  guard out.exitCode == 0 else { return nil }
  let path = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  return path.isEmpty ? nil : path
}

private func runXcpretty(rawLog: String, executablePath: String) -> String? {
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

