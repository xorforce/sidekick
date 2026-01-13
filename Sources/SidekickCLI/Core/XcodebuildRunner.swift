import Foundation

final class DataAccumulator {
  var data = Data()
}

struct XcodebuildRunResult {
  let exitCode: Int32
  let rawLog: String
  let prettyLog: String?
}

enum XcodebuildError: Error {
  case failed(exitCode: Int32, rawLog: String, prettyLog: String?, errors: [String])

  var exitCode: Int32 {
    switch self {
    case .failed(let exitCode, _, _, _):
      return exitCode
    }
  }

  var rawLog: String {
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

func runXcodebuild(arguments: [String]) throws -> XcodebuildRunResult {
  let (process, stdoutPipe, stderrPipe) = makeXcodebuildProcess(arguments: arguments)
  let stdoutData = DataAccumulator()
  let stderrData = DataAccumulator()

  stream(pipe: stdoutPipe, into: stdoutData)
  stream(pipe: stderrPipe, into: stderrData)

  try start(process: process)
  process.waitUntilExit()
  clearStreaming(pipe: stdoutPipe)
  clearStreaming(pipe: stderrPipe)

  drainRemaining(pipe: stdoutPipe, into: stdoutData)
  drainRemaining(pipe: stderrPipe, into: stderrData)

  let exitCode = process.terminationStatus
  let combined = combine(stdout: stdoutData.data, stderr: stderrData.data)
  let rawLog = String(decoding: combined, as: UTF8.self)
  let prettyLog = runXcprettyIfAvailable(rawLog: rawLog)

  if exitCode != 0 {
    let errors = extractErrors(from: prettyLog ?? rawLog)
    throw XcodebuildError.failed(exitCode: exitCode, rawLog: rawLog, prettyLog: prettyLog, errors: errors)
  }

  return XcodebuildRunResult(exitCode: exitCode, rawLog: rawLog, prettyLog: prettyLog)
}

private func makeXcodebuildProcess(arguments: [String]) -> (Process, Pipe, Pipe) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
  process.arguments = arguments

  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe
  return (process, stdoutPipe, stderrPipe)
}

private func start(process: Process) throws {
  do {
    try process.run()
  } catch {
    throw XcodebuildError.failed(
      exitCode: 1,
      rawLog: "Failed to spawn xcodebuild: \(error)",
      prettyLog: nil,
      errors: ["Failed to spawn xcodebuild: \(error)"]
    )
  }
}

private func stream(pipe: Pipe, into buffer: DataAccumulator) {
  pipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty else { return }
    buffer.data.append(data)
    FileHandle.standardOutput.write(data)
  }
}

private func clearStreaming(pipe: Pipe) {
  pipe.fileHandleForReading.readabilityHandler = nil
}

private func drainRemaining(pipe: Pipe, into buffer: DataAccumulator) {
  buffer.data.append(pipe.fileHandleForReading.readDataToEndOfFile())
}

private func combine(stdout: Data, stderr: Data) -> Data {
  var combined = Data()
  combined.append(stdout)
  combined.append(stderr)
  return combined
}

