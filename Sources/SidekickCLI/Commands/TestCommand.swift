import ArgumentParser
import Foundation

struct TestCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "test",
    abstract: "Run tests via xcodebuild test (optionally using a test plan)"
  )

  @Option(name: .customLong("profile"), help: "Use named profile (future use)")
  var profile: String?

  @Option(name: .customLong("workspace"), help: "Path to .xcworkspace file")
  var workspace: String?

  @Option(name: .customLong("project"), help: "Path to .xcodeproj file")
  var project: String?

  @Option(name: .customLong("scheme"), help: "Test scheme name")
  var scheme: String?

  @Option(name: .customLong("configuration"), help: "Build configuration (Debug/Release)")
  var buildConfiguration: String?

  @Option(name: .customLong("platform"), help: "Platform: ios-sim, ios-device, macos")
  var platform: Platform?

  @Option(name: .customLong("test-plan"), help: "Test plan name (from xcodebuild -showTestPlans)")
  var testPlan: String?

  @Flag(name: .customLong("clean"), help: "Clean before testing")
  var clean: Bool = false

  func run() throws {
    try TestFlow(
      workspace: workspace,
      project: project,
      scheme: scheme,
      buildConfiguration: buildConfiguration,
      platform: platform,
      testPlan: testPlan,
      clean: clean
    ).run()
  }
}

private struct TestFlow {
  let workspace: String?
  let project: String?
  let scheme: String?
  let buildConfiguration: String?
  let platform: Platform?
  let testPlan: String?
  let clean: Bool

  func run() throws {
    let config = loadConfigIfAvailable()
    let options = makeOptions(config: config)
    let args = makeXcodebuildArguments(options: options, action: .test)
    let logPaths = try createLogPaths(action: "test")

    do {
      let result = try runXcodebuild(arguments: args)
      try writeLogs(result: result, to: logPaths)
      print("\n✅ Tests succeeded")
      printLogs(logPaths: logPaths, prettyIncluded: result.prettyLog != nil)
    } catch {
      try handleXcodebuildFailure(actionLabel: "Tests", error: error, logPaths: logPaths)
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
      testPlan: testPlan ?? config?.testPlan
    )
  }

  private func writeLogs(result: XcodebuildRunResult, to logPaths: LogPaths) throws {
    try result.rawLog.write(to: logPaths.rawLogURL, atomically: true, encoding: .utf8)
    let prettyToSave = result.prettyLog ?? result.rawLog
    try prettyToSave.write(to: logPaths.prettyLogURL, atomically: true, encoding: .utf8)
  }
}

