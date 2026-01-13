import Foundation

struct LogPaths {
  let baseDir: URL
  let rawLogURL: URL
  let prettyLogURL: URL
}

func createLogPaths(action: String) throws -> LogPaths {
  let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
  let baseDir = URL(fileURLWithPath: ".sidekick/logs/\(action)-\(timestamp)", isDirectory: true)
  try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

  return LogPaths(
    baseDir: baseDir,
    rawLogURL: baseDir.appendingPathComponent("raw.log"),
    prettyLogURL: baseDir.appendingPathComponent("pretty.log")
  )
}

