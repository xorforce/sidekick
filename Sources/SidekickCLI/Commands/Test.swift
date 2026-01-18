import ArgumentParser
import Foundation

extension Sidekick {
  struct Test: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Run tests for simulator, device, or macOS"
    )

    @Option(name: .customLong("path"), help: "Path to project directory")
    var path: String?

    @Option(name: .customLong("workspace"), help: "Path to .xcworkspace file")
    var workspace: String?

    @Option(name: .customLong("project"), help: "Path to .xcodeproj file")
    var project: String?

    @Option(name: .customLong("scheme"), help: "Test scheme name")
    var scheme: String?

    @Option(name: .customLong("configuration"), help: "Build configuration (Debug/Release)")
    var configuration: String?

    @Option(name: .customLong("config"), help: "Path to Sidekick config file")
    var configPath: String?

    @Option(name: .customLong("platform"), help: "Platform: ios-sim, ios-device, macos")
    var platform: Platform?

    @Option(name: .customLong("test-plan"), help: "Test plan name or .xctestplan path")
    var testPlan: String?

    @Option(name: .customLong("derived-data"), help: "Derived data path")
    var derivedData: String?

    @Flag(
      name: .customLong("allow-provisioning-updates"),
      help: "Allow Xcode to update provisioning profiles automatically"
    )
    var allowProvisioningUpdates: Bool = false

    @Flag(
      name: .customLong("verbose"),
      help: "Stream full xcodebuild output"
    )
    var verbose: Bool = false

    @Flag(name: .customLong("clean"), help: "Clean before testing")
    var clean: Bool = false

    func run() throws {
      try changeToProjectDirectory(path)
      let config = loadConfigAndReport(configPath: configPath)
      try runHookIfNeeded(config: config, command: .test, phase: .pre)

      let settings = resolveTestSettings(
        config: config,
        scheme: scheme,
        configuration: configuration,
        platform: platform,
        testPlan: testPlan,
        allowProvisioningUpdates: allowProvisioningUpdates,
        workspace: workspace,
        project: project,
        derivedData: derivedData
      )
      printTestSettings(settings, clean: clean)
      let destination = try resolveTestDestination(platform: settings.platform, config: config)
      printTestDestination(destination, requestedPlatform: settings.platform)

      let args = buildTestArgs(
        workspace: settings.workspace,
        project: settings.project,
        scheme: settings.scheme,
        configuration: settings.configuration,
        destination: destination,
        testPlan: settings.testPlan?.name,
        derivedData: settings.derivedData,
        allowProvisioningUpdates: settings.allowProvisioningUpdates,
        clean: clean
      )

      let result = try runTests(args: args, verbose: verbose)
      let output = result.stdout + result.stderr
      let summary = parseTestCaseResults(output: output)
      printTestSummary(summary)

      if result.exitCode != 0 {
        print("❌ Tests failed")
        let errors = extractBuildErrors(from: output)
        if !errors.isEmpty {
          print("\nErrors:")
          errors.forEach { print("  \($0)") }
        }
        throw ExitCode(result.exitCode)
      }

      print("✅ Tests succeeded")
      try runHookIfNeeded(config: config, command: .test, phase: .post)
    }
  }
}

private struct TestPlanSelection {
  let name: String
  let source: String?
}

private struct TestResolvedSettings {
  let scheme: String
  let configuration: String
  let platform: Platform
  let allowProvisioningUpdates: Bool
  let workspace: String?
  let project: String?
  let derivedData: String?
  let testPlan: TestPlanSelection?
}

private struct TestDestination {
  let platform: Platform
  let type: String?
  let name: String?
  let id: String?
  let destination: String
}

private struct TestTarget {
  let name: String
  let id: String
  let isDevice: Bool
}

private struct TestOutputSummary {
  let passed: [String]
  let failed: [String]
}

private enum TestError: Error, CustomStringConvertible {
  case noTargetAvailable

  var description: String {
    switch self {
    case .noTargetAvailable:
      return "No device or simulator available. Run 'sidekick configure --init' to configure."
    }
  }
}

private func changeToProjectDirectory(_ path: String?) throws {
  guard let path else { return }
  let expandedPath = NSString(string: path).expandingTildeInPath
  print("📂 Changing to project directory: \(expandedPath)")
  guard FileManager.default.changeCurrentDirectoryPath(expandedPath) else {
    print("❌ Failed to change directory to: \(expandedPath)")
    throw ExitCode.failure
  }
}

private func loadConfigAndReport(configPath: String?) -> SidekickConfig? {
  print("⚙️  Loading configuration...")
  let config = loadConfigIfAvailable(configPath: configPath)
  if config != nil {
    if let configPath {
      print("   ✓ Found config at \(configPath)")
    } else {
      print("   ✓ Found .sidekick/config.json")
    }
  } else {
    if let configPath {
      print("   ⚠️  No config file found at \(configPath), using defaults")
    } else {
      print("   ⚠️  No config file found, using defaults")
    }
  }
  return config
}

private func resolveTestSettings(
  config: SidekickConfig?,
  scheme: String?,
  configuration: String?,
  platform: Platform?,
  testPlan: String?,
  allowProvisioningUpdates: Bool,
  workspace: String?,
  project: String?,
  derivedData: String?
) -> TestResolvedSettings {
  let resolvedPlan = resolveTestPlanSelection(testPlan ?? config?.testPlanPath)
  return TestResolvedSettings(
    scheme: scheme ?? config?.scheme ?? "clavis",
    configuration: configuration ?? config?.configuration ?? "Debug",
    platform: platform ?? config?.platform ?? .iosSim,
    allowProvisioningUpdates: allowProvisioningUpdates || (config?.allowProvisioningUpdates ?? false),
    workspace: workspace ?? config?.workspace,
    project: project ?? config?.project,
    derivedData: derivedData ?? config?.derivedDataPath,
    testPlan: resolvedPlan
  )
}

private func printTestSettings(_ settings: TestResolvedSettings, clean: Bool) {
  if let plan = settings.testPlan {
    warnIfMissingTestPlanFile(plan)
  }
  print("\n🧪 Preparing tests...")
  print("   Scheme: \(settings.scheme)")
  print("   Configuration: \(settings.configuration)")
  print("   Platform: \(settings.platform.rawValue)")
  if let plan = settings.testPlan {
    print("   Test plan: \(plan.name)")
  }
  if let workspace = settings.workspace {
    print("   Workspace: \(workspace)")
  } else if let project = settings.project {
    print("   Project: \(project)")
  }
  if let derivedData = settings.derivedData {
    print("   Derived Data: \(derivedData)")
  }
  if settings.allowProvisioningUpdates {
    print("   Provisioning updates: Enabled")
  }
  if clean {
    print("   Clean test: Yes")
  }
}

private func runTests(args: [String], verbose: Bool) throws -> ProcessResult {
  if verbose {
    print("\n🔎 Streaming xcodebuild output...")
    return try runProcessStreaming(executable: "/usr/bin/xcodebuild", arguments: args)
  }
  return try withSpinner(message: "Testing") {
    try runProcess(executable: "/usr/bin/xcodebuild", arguments: args)
  }
}

private func resolveTestPlanSelection(_ raw: String?) -> TestPlanSelection? {
  guard let raw else { return nil }
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }
  let expanded = NSString(string: trimmed).expandingTildeInPath
  let usesPath = trimmed.contains("/") || trimmed.hasSuffix(".xctestplan")
  if usesPath {
    let url = URL(fileURLWithPath: expanded)
    let name = url.deletingPathExtension().lastPathComponent
    return TestPlanSelection(name: name, source: url.path)
  }
  return TestPlanSelection(name: trimmed, source: nil)
}

private func warnIfMissingTestPlanFile(_ selection: TestPlanSelection) {
  guard let source = selection.source else { return }
  if !FileManager.default.fileExists(atPath: source) {
    print("   ⚠️  Test plan file not found at \(source); using name '\(selection.name)'")
  }
}

private func resolveTestDestination(platform: Platform, config: SidekickConfig?) throws -> TestDestination {
  switch platform {
  case .macos:
    return TestDestination(
      platform: .macos,
      type: nil,
      name: nil,
      id: nil,
      destination: "platform=macOS"
    )
  case .iosSim:
    let target = try resolveSimulatorTarget(config: config)
    return TestDestination(
      platform: .iosSim,
      type: "simulator",
      name: target.name,
      id: target.id,
      destination: "platform=iOS Simulator,id=\(target.id)"
    )
  case .iosDevice:
    if let device = resolveDeviceTarget(config: config) {
      return TestDestination(
        platform: .iosDevice,
        type: "device",
        name: device.name,
        id: device.id,
        destination: "platform=iOS,id=\(device.id)"
      )
    }
    let fallback = try resolveSimulatorTarget(config: config)
    return TestDestination(
      platform: .iosSim,
      type: "simulator",
      name: fallback.name,
      id: fallback.id,
      destination: "platform=iOS Simulator,id=\(fallback.id)"
    )
  }
}

private func resolveDeviceTarget(config: SidekickConfig?) -> TestTarget? {
  guard let deviceUDID = config?.deviceUDID, !deviceUDID.isEmpty,
        let deviceName = config?.deviceName else {
    return nil
  }
  if isDeviceConnectedViaUSB(udid: deviceUDID) {
    return TestTarget(name: deviceName, id: deviceUDID, isDevice: true)
  }
  return nil
}

private func resolveSimulatorTarget(config: SidekickConfig?) throws -> TestTarget {
  if let simulatorUDID = config?.simulatorUDID, !simulatorUDID.isEmpty,
     let simulatorName = config?.simulatorName {
    return TestTarget(name: simulatorName, id: simulatorUDID, isDevice: false)
  }
  if let simulator = try? findAnyIPhoneSimulator() {
    return TestTarget(name: simulator.name, id: simulator.udid, isDevice: false)
  }
  throw TestError.noTargetAvailable
}

private func printTestDestination(_ destination: TestDestination, requestedPlatform: Platform) {
  if destination.platform == .macos {
    print("   Target: macOS")
    return
  }
  if requestedPlatform == .iosDevice, destination.type == "simulator" {
    print("   ⚠️  Device not available; falling back to simulator")
  }
  if let name = destination.name, let id = destination.id, let type = destination.type {
    print("   Target: \(type) - \(name) (\(id))")
  }
}

private func buildTestArgs(
  workspace: String?,
  project: String?,
  scheme: String,
  configuration: String,
  destination: TestDestination,
  testPlan: String?,
  derivedData: String?,
  allowProvisioningUpdates: Bool,
  clean: Bool
) -> [String] {
  var args = baseTestArgs(
    workspace: workspace,
    project: project,
    scheme: scheme,
    configuration: configuration
  )
  appendSdkArgs(for: destination.platform, to: &args)
  args.append(contentsOf: ["-destination", destination.destination])
  appendDerivedData(derivedData, to: &args)
  appendTestPlan(testPlan, to: &args)
  if allowProvisioningUpdates {
    args.append("-allowProvisioningUpdates")
  }
  if clean {
    args.append("clean")
  }
  args.append("test")
  return args
}

private func baseTestArgs(
  workspace: String?,
  project: String?,
  scheme: String,
  configuration: String
) -> [String] {
  var args: [String] = []
  if let workspace {
    args.append(contentsOf: ["-workspace", workspace])
  } else if let project {
    args.append(contentsOf: ["-project", project])
  }
  args.append(contentsOf: ["-scheme", scheme])
  args.append(contentsOf: ["-configuration", configuration])
  return args
}

private func appendSdkArgs(for platform: Platform, to args: inout [String]) {
  switch platform {
  case .iosSim:
    args.append(contentsOf: ["-sdk", "iphonesimulator"])
  case .iosDevice:
    args.append(contentsOf: ["-sdk", "iphoneos"])
  case .macos:
    args.append(contentsOf: ["-sdk", "macosx"])
  }
}

private func appendDerivedData(_ derivedData: String?, to args: inout [String]) {
  guard let derivedData else { return }
  args.append(contentsOf: ["-derivedDataPath", derivedData])
}

private func appendTestPlan(_ testPlan: String?, to args: inout [String]) {
  guard let testPlan else { return }
  args.append(contentsOf: ["-testPlan", testPlan])
}

private func parseTestCaseResults(output: String) -> TestOutputSummary {
  let pattern = #"Test Case '([^']+)' (passed|failed)"#
  guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
    return TestOutputSummary(passed: [], failed: [])
  }

  var passed: [String] = []
  var failed: [String] = []
  let range = NSRange(location: 0, length: output.utf16.count)
  for match in regex.matches(in: output, options: [], range: range) {
    guard let nameRange = Range(match.range(at: 1), in: output),
          let statusRange = Range(match.range(at: 2), in: output) else { continue }
    let name = String(output[nameRange])
    let status = String(output[statusRange])
    if status == "passed" {
      appendUnique(name, to: &passed)
    } else if status == "failed" {
      appendUnique(name, to: &failed)
    }
  }

  return TestOutputSummary(passed: passed, failed: failed)
}

private func appendUnique(_ value: String, to list: inout [String]) {
  if !list.contains(value) {
    list.append(value)
  }
}

private func printTestSummary(_ summary: TestOutputSummary) {
  guard !summary.passed.isEmpty || !summary.failed.isEmpty else {
    print("\n🧪 No test case results detected in output.")
    return
  }
  print("\n🧪 Test Results")
  print("   Passed: \(summary.passed.count)")
  print("   Failed: \(summary.failed.count)")
  if !summary.failed.isEmpty {
    print("\nFailed tests:")
    printTestList(summary.failed, prefix: "  ✗")
  }
  if !summary.passed.isEmpty {
    print("\nPassed tests:")
    printTestList(summary.passed, prefix: "  ✓")
  }
}

private func printTestList(_ tests: [String], prefix: String, limit: Int = 25) {
  let capped = tests.prefix(limit)
  for name in capped {
    print("\(prefix) \(name)")
  }
  if tests.count > limit {
    print("  ... \(tests.count - limit) more")
  }
}
