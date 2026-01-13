import Foundation

struct ProcessResult {
  let exitCode: Int32
  let stdout: String
  let stderr: String
}

enum ProcessRunError: Error, CustomStringConvertible {
  case failedToStart(underlying: Error)

  var description: String {
    switch self {
    case .failedToStart(let underlying):
      return "Failed to start process: \(underlying)"
    }
  }
}

func runProcess(
  executable: String,
  arguments: [String],
  input: Data? = nil
) throws -> ProcessResult {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments

  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe

  if let input {
    let stdinPipe = Pipe()
    process.standardInput = stdinPipe
    stdinPipe.fileHandleForWriting.write(input)
    stdinPipe.fileHandleForWriting.closeFile()
  }

  do {
    try process.run()
  } catch {
    throw ProcessRunError.failedToStart(underlying: error)
  }

  process.waitUntilExit()

  let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
  let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

  return ProcessResult(
    exitCode: process.terminationStatus,
    stdout: String(decoding: stdoutData, as: UTF8.self),
    stderr: String(decoding: stderrData, as: UTF8.self)
  )
}

