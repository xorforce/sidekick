import ArgumentParser
import Foundation

struct InitCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "init",
    abstract: "Initialize sidekick defaults for this project"
  )

  @Option(name: .customLong("path"), help: "Project root to scan (defaults to current directory)")
  var path: String?

  @Flag(name: .customLong("non-interactive"), help: "Use first detected options without prompts")
  var nonInteractive: Bool = false

  func run() throws {
    try InitFlow(path: path, nonInteractive: nonInteractive).run()
  }
}

private struct InitFlow {
  let path: String?
  let nonInteractive: Bool

  func run() throws {
    let root = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)
    let projects = detectProjects(in: root)
    try ensureProjectsFound(projects, root: root)

    let project = chooseProject(from: projects, nonInteractive: nonInteractive)
    let schemes = listSchemes(for: project)
    let configurations = listConfigurations(for: project)

    let scheme = try chooseScheme(schemes: schemes)
    let configuration = chooseConfiguration(configurations: configurations)
    let platform = choosePlatform()
    let testPlan = chooseTestPlan(project: project, scheme: scheme)

    let config = SidekickConfig(
      workspace: project.workspacePath,
      project: project.projectPath,
      scheme: scheme,
      configuration: configuration,
      platform: platform,
      derivedDataPath: nil,
      testPlan: testPlan
    )

    try saveConfig(config, root: root)
    printSavedConfig(config: config, root: root)
  }

  private func chooseScheme(schemes: [String]) throws -> String {
    if schemes.isEmpty {
      return try promptForMissingScheme()
    }
    return chooseOption(prompt: "Select scheme", options: schemes, nonInteractive: nonInteractive) ?? schemes.first!
  }

  private func promptForMissingScheme() throws -> String {
    print("No schemes detected. Enter scheme name: ", terminator: "")
    let scheme = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if scheme.isEmpty {
      print("Scheme is required.")
      throw ExitCode(1)
    }
    return scheme
  }

  private func chooseConfiguration(configurations: [String]) -> String {
    let options = configurations.isEmpty ? ["Debug", "Release"] : configurations
    return chooseOption(prompt: "Select configuration", options: options, nonInteractive: nonInteractive) ?? "Debug"
  }

  private func choosePlatform() -> Platform? {
    let platformOptions = Platform.allCases.map { $0.rawValue }
    let platformRaw = chooseOption(
      prompt: "Select platform",
      options: platformOptions,
      nonInteractive: nonInteractive
    ) ?? Platform.iosSim.rawValue
    return Platform(rawValue: platformRaw)
  }

  private func chooseTestPlan(project: ProjectEntry, scheme: String) -> String? {
    let plans = listTestPlans(for: project, scheme: scheme)
    guard !plans.isEmpty else { return nil }

    if nonInteractive {
      return plans.first
    }

    let options = ["None"] + plans
    let selection = chooseOption(prompt: "Select test plan", options: options, nonInteractive: nonInteractive)
    if selection == "None" { return nil }
    return selection
  }
}

private func ensureProjectsFound(_ projects: [ProjectEntry], root: URL) throws {
  guard !projects.isEmpty else {
    print("No .xcworkspace or .xcodeproj found under \(root.path).")
    throw ExitCode(1)
  }
}

private func printSavedConfig(config: SidekickConfig, root: URL) {
  print("""
Saved sidekick config:
  Workspace: \(config.workspace ?? "-")
  Project: \(config.project ?? "-")
  Scheme: \(config.scheme ?? "-")
  Configuration: \(config.configuration ?? "-")
  Platform: \(config.platform?.rawValue ?? "-")
  Test plan: \(config.testPlan ?? "-")
  Path: \(configFilePath(root: root).path)
""")
}

