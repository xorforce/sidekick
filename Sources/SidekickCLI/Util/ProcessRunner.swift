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
  try runProcessInternal(
    executable: executable,
    arguments: arguments,
    input: input,
    streamOutput: false
  )
}

func runProcessStreaming(
  executable: String,
  arguments: [String]
) throws -> ProcessResult {
  try runProcessInternal(
    executable: executable,
    arguments: arguments,
    input: nil,
    streamOutput: true
  )
}

private final class DataBox {
  var value = Data()
}

private func runProcessInternal(
  executable: String,
  arguments: [String],
  input: Data?,
  streamOutput: Bool
) throws -> ProcessResult {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments

  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe

  let stdoutData = DataBox()
  let stderrData = DataBox()

  stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if data.isEmpty { return }
    stdoutData.value.append(data)
    if streamOutput {
      FileHandle.standardOutput.write(data)
    }
  }

  stderrPipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if data.isEmpty { return }
    stderrData.value.append(data)
    if streamOutput {
      FileHandle.standardError.write(data)
    }
  }

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
  stdoutPipe.fileHandleForReading.readabilityHandler = nil
  stderrPipe.fileHandleForReading.readabilityHandler = nil

  stdoutData.value.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
  stderrData.value.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

  return ProcessResult(
    exitCode: process.terminationStatus,
    stdout: String(decoding: stdoutData.value, as: UTF8.self),
    stderr: String(decoding: stderrData.value, as: UTF8.self)
  )
}

