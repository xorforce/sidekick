import ArgumentParser
import Foundation

struct BuildCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "build",
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
  var buildConfiguration: String?

  @Option(name: .customLong("platform"), help: "Platform: ios-sim, ios-device, macos")
  var platform: Platform?

  @Flag(name: .customLong("clean"), help: "Clean before building")
  var clean: Bool = false

  func run() throws {
    try BuildFlow(
      workspace: workspace,
      project: project,
      scheme: scheme,
      buildConfiguration: buildConfiguration,
      platform: platform,
      clean: clean
    ).run()
  }
}

private struct BuildFlow {
  let workspace: String?
  let project: String?
  let scheme: String?
  let buildConfiguration: String?
  let platform: Platform?
  let clean: Bool

  func run() throws {
    let config = loadConfigIfAvailable()
    let options = makeOptions(config: config)
    let args = makeXcodebuildArguments(options: options, action: .build)
    let logPaths = try createLogPaths(action: "build")

    do {
      let result = try runXcodebuild(arguments: args)
      try writeLogs(result: result, to: logPaths)
      print("\n✅ Build succeeded")
      printLogs(logPaths: logPaths, prettyIncluded: result.prettyLog != nil)
    } catch {
      try handleXcodebuildFailure(actionLabel: "Build", error: error, logPaths: logPaths)
    }
  }

  private func makeOptions(config: SidekickConfig?) -> XcodebuildOptions {
    XcodebuildOptions(
      workspace: workspace ?? config?.workspace,
      project: project ?? config?.project,
      scheme: scheme ?? config?.scheme ?? "clavis",
      configuration: buildConfiguration ?? config?.configuration ?? "Debug",
      platform: platform ?? config?.platform,
      clean: clean,
      testPlan: nil
    )
  }

  private func writeLogs(result: XcodebuildRunResult, to logPaths: LogPaths) throws {
    try result.rawLog.write(to: logPaths.rawLogURL, atomically: true, encoding: .utf8)
    let prettyToSave = result.prettyLog ?? result.rawLog
    try prettyToSave.write(to: logPaths.prettyLogURL, atomically: true, encoding: .utf8)
  }
}

