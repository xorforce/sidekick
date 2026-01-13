import Foundation

func listSchemes(for entry: ProjectEntry) -> [String] {
  let args = listArgs(for: entry)
  let output = runProcess(executablePath: "/usr/bin/xcodebuild", arguments: args)
  guard output.exitCode == 0 else { return [] }
  return parseXcodebuildListSection(output: output.stdout, section: "Schemes")
}

func listConfigurations(for entry: ProjectEntry) -> [String] {
  let args = listArgs(for: entry)
  let output = runProcess(executablePath: "/usr/bin/xcodebuild", arguments: args)
  guard output.exitCode == 0 else { return [] }
  return parseXcodebuildListSection(output: output.stdout, section: "Build Configurations")
}

func listTestPlans(for entry: ProjectEntry, scheme: String) -> [String] {
  let baseArgs = projectSelectorArgs(for: entry)
  let args = baseArgs + ["-scheme", scheme, "-showTestPlans"]
  let output = runProcess(executablePath: "/usr/bin/xcodebuild", arguments: args)
  guard output.exitCode == 0 else { return [] }
  return parseXcodebuildTestPlans(output: output.stdout + output.stderr)
}

private func listArgs(for entry: ProjectEntry) -> [String] {
  projectSelectorArgs(for: entry) + ["-list"]
}

private func projectSelectorArgs(for entry: ProjectEntry) -> [String] {
  switch entry.kind {
  case .workspace:
    return ["-workspace", entry.url.path]
  case .project:
    return ["-project", entry.url.path]
  }
}

private func parseXcodebuildTestPlans(output: String) -> [String] {
  let lines = output.split(separator: "\n").map {
    $0.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var plans: [String] = []
  var inSection = false

  for line in lines where !line.isEmpty {
    let lower = line.lowercased()
    if lower.contains("test plan") && lower.contains("scheme") {
      inSection = true
      continue
    }
    if !inSection { continue }
    if lower.hasPrefix("if no test plans") { break }
    if lower.hasPrefix("note:") { break }
    if lower.hasSuffix(":") { break }
    plans.append(line)
  }

  return plans
}

