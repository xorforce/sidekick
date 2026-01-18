import ArgumentParser
import Foundation

func buildSidekickConfig(
  root: URL,
  existingConfig: SidekickConfig?,
  nonInteractive: Bool,
  allowProvisioningUpdates: Bool,
  archiveOutput: String?,
  selectedConfig: SidekickConfig?
) throws -> SidekickConfig {
  let project = try resolveProject(
    root: root,
    nonInteractive: nonInteractive,
    selectedConfig: selectedConfig
  )
  let scheme = try resolveScheme(
    project: project,
    nonInteractive: nonInteractive,
    selectedConfig: selectedConfig
  )
  let configuration = resolveConfiguration(
    project: project,
    nonInteractive: nonInteractive,
    selectedConfig: selectedConfig
  )
  let platform = resolvePlatform(
    nonInteractive: nonInteractive,
    selectedConfig: selectedConfig
  )

  var config = SidekickConfig(
    workspace: project.workspacePath,
    project: project.projectPath,
    scheme: scheme,
    configuration: configuration,
    platform: platform,
    allowProvisioningUpdates: allowProvisioningUpdates,
    archiveOutputPath: archiveOutput ?? selectedConfig?.archiveOutputPath,
    testPlanPath: selectedConfig?.testPlanPath ?? existingConfig?.testPlanPath,
    hooks: existingConfig?.hooks,
    setupJob: existingConfig?.setupJob,
    setupJobCompleted: existingConfig?.setupJobCompleted ?? false,
    simulatorName: selectedConfig?.simulatorName,
    simulatorUDID: selectedConfig?.simulatorUDID,
    deviceName: selectedConfig?.deviceName,
    deviceUDID: selectedConfig?.deviceUDID
  )

  if platform == .iosSim {
    applyDefaultSimulator(to: &config, nonInteractive: nonInteractive)
  }

  if platform == .iosDevice {
    applyDefaultDeviceIfAny(to: &config, nonInteractive: nonInteractive)
  }

  return config
}

private func resolveProject(
  root: URL,
  nonInteractive: Bool,
  selectedConfig: SidekickConfig?
) throws -> ProjectEntry {
  let projects = withSpinner(message: "Detecting projects") {
    detectProjects(in: root)
  }

  guard !projects.isEmpty else {
    print("No .xcworkspace or .xcodeproj found under \(root.path).")
    throw ExitCode(1)
  }

  let selectedPath = selectedConfig?.workspace ?? selectedConfig?.project
  return chooseProject(from: projects, nonInteractive: nonInteractive, selectedPath: selectedPath)
}

private func resolveScheme(
  project: ProjectEntry,
  nonInteractive: Bool,
  selectedConfig: SidekickConfig?
) throws -> String {
  let schemes = withSpinner(message: "Listing schemes") {
    listSchemes(for: project)
  }
  return try chooseScheme(
    schemes: schemes,
    nonInteractive: nonInteractive,
    selected: selectedConfig?.scheme
  )
}

private func resolveConfiguration(
  project: ProjectEntry,
  nonInteractive: Bool,
  selectedConfig: SidekickConfig?
) -> String {
  let configurations = withSpinner(message: "Listing configurations") {
    listConfigurations(for: project)
  }
  let fallback = configurations.isEmpty ? ["Debug", "Release"] : configurations
  return chooseOption(
    prompt: "Select configuration",
    options: fallback,
    nonInteractive: nonInteractive,
    selected: selectedConfig?.configuration
  ) ?? "Debug"
}

private func resolvePlatform(
  nonInteractive: Bool,
  selectedConfig: SidekickConfig?
) -> Platform? {
  let options = Platform.allCases.map { $0.rawValue }
  let platformRaw = chooseOption(
    prompt: "Select platform",
    options: options,
    nonInteractive: nonInteractive,
    selected: selectedConfig?.platform?.rawValue
  ) ?? Platform.iosSim.rawValue
  return Platform(rawValue: platformRaw)
}
