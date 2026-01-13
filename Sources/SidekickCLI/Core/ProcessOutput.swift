import Foundation

struct ProcessOutput {
  let exitCode: Int32
  let stdout: String
  let stderr: String
}

func runProcess(
  executablePath: String,
  arguments: [String]
) -> ProcessOutput {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executablePath)
  process.arguments = arguments

  let stdoutPipe = Pipe()
  let stderrPipe = Pipe()
  process.standardOutput = stdoutPipe
  process.standardError = stderrPipe

  do {
    try process.run()
  } catch {
    return ProcessOutput(exitCode: 1, stdout: "", stderr: "Failed to spawn \(executablePath): \(error)")
  }

  process.waitUntilExit()

  let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
  let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

  return ProcessOutput(
    exitCode: process.terminationStatus,
    stdout: String(decoding: stdoutData, as: UTF8.self),
    stderr: String(decoding: stderrData, as: UTF8.self)
  )
}

