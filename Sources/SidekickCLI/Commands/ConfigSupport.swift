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
  let projectSelection = try resolveProject(
    root: root,
    nonInteractive: nonInteractive,
    selectedConfig: selectedConfig
  )
  let scheme = try resolveScheme(
    project: projectSelection.project,
    cachedSchemes: projectSelection.schemes,
    nonInteractive: nonInteractive,
    selectedConfig: selectedConfig
  )
  let configuration = resolveConfiguration(
    project: projectSelection.project,
    nonInteractive: nonInteractive,
    selectedConfig: selectedConfig
  )
  let platform = resolvePlatform(
    nonInteractive: nonInteractive,
    selectedConfig: selectedConfig
  )

  var config = SidekickConfig(
    workspace: projectSelection.project.workspacePath,
    project: projectSelection.project.projectPath,
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

private struct ResolvedProjectSelection {
  let project: ProjectEntry
  let schemes: [String]?
}

private func resolveProject(
  root: URL,
  nonInteractive: Bool,
  selectedConfig: SidekickConfig?
) throws -> ResolvedProjectSelection {
  let projects = withSpinner(message: "Detecting projects") {
    detectProjects(in: root)
  }

  guard !projects.isEmpty else {
    print("No .xcworkspace or .xcodeproj found under \(root.path).")
    throw ExitCode(1)
  }

  let selectedPath = selectedConfig?.workspace ?? selectedConfig?.project
  if nonInteractive, selectedPath == nil {
    return preferredProject(from: projects)
  }
  let chosenProject = chooseProject(
    from: projects,
    nonInteractive: nonInteractive,
    selectedPath: selectedPath
  )
  return resolvedSelection(for: chosenProject, among: projects)
}

private func preferredProject(from projects: [ProjectEntry]) -> ResolvedProjectSelection {
  for project in projects {
    let schemes = listSchemes(for: project)
    if !schemes.isEmpty {
      return ResolvedProjectSelection(project: project, schemes: schemes)
    }
  }
  return ResolvedProjectSelection(project: projects.first!, schemes: nil)
}

private func resolvedSelection(
  for project: ProjectEntry,
  among projects: [ProjectEntry]
) -> ResolvedProjectSelection {
  let schemes = listSchemes(for: project)
  if !schemes.isEmpty {
    return ResolvedProjectSelection(project: project, schemes: schemes)
  }

  if let fallback = fallbackProject(for: project, among: projects) {
    let fallbackSchemes = listSchemes(for: fallback)
    if !fallbackSchemes.isEmpty {
      return ResolvedProjectSelection(project: fallback, schemes: fallbackSchemes)
    }
  }

  return ResolvedProjectSelection(project: project, schemes: nil)
}

private func fallbackProject(
  for project: ProjectEntry,
  among projects: [ProjectEntry]
) -> ProjectEntry? {
  guard project.kind == .workspace else { return nil }
  let workspaceBaseName = project.url.deletingPathExtension().lastPathComponent
  return projects.first { candidate in
    candidate.kind == .project
      && candidate.url.deletingPathExtension().lastPathComponent == workspaceBaseName
  }
}

private func resolveScheme(
  project: ProjectEntry,
  cachedSchemes: [String]?,
  nonInteractive: Bool,
  selectedConfig: SidekickConfig?
) throws -> String {
  let schemes = cachedSchemes ?? withSpinner(message: "Listing schemes") {
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
