import ArgumentParser
import Foundation

func handleXcodebuildFailure(actionLabel: String, error: Error, logPaths: LogPaths) throws -> Never {
  print("\n❌ \(actionLabel) failed")

  if let xcodeError = error as? XcodebuildError {
    try? xcodeError.rawLog.write(to: logPaths.rawLogURL, atomically: true, encoding: .utf8)
    let prettyToSave = xcodeError.prettyLog ?? xcodeError.rawLog
    try? prettyToSave.write(to: logPaths.prettyLogURL, atomically: true, encoding: .utf8)
    printErrors(xcodeError.errors)
    print("\nSee full log: \(logPaths.rawLogURL.path)")
    throw ExitCode(xcodeError.exitCode)
  }

  print("Error: \(error.localizedDescription)")
  throw ExitCode.failure
}

