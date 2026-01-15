import ArgumentParser
import Foundation

extension Sidekick {
  struct Setup: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Run the one-time setup job for this project"
    )

    @Option(name: .customLong("path"), help: "Project root containing .sidekick/config.json")
    var path: String?

    func run() throws {
      let root = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)
      if let path {
        let expandedPath = NSString(string: path).expandingTildeInPath
        print("📂 Changing to project directory: \(expandedPath)")
        guard FileManager.default.changeCurrentDirectoryPath(expandedPath) else {
          print("❌ Failed to change directory to: \(expandedPath)")
          throw ExitCode.failure
        }
      }

      guard var config = loadConfigIfAvailable(root: root) else {
        print("⚠️  No .sidekick/config.json found at \(root.path); nothing to run.")
        return
      }

      guard config.setupJob != nil else {
        print("⚠️  No setup job configured; nothing to run.")
        return
      }

      guard config.setupJobCompleted == false else {
        print("✅ Setup job already completed; skipping.")
        return
      }

      try runSetupJobIfNeeded(config: config)
      config.setupJobCompleted = true
      try saveConfig(config, root: root)
      print("✅ Setup job completed.")
    }
  }
}
