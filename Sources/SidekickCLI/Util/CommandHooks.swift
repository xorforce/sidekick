import ArgumentParser
import Foundation

enum HookCommand {
  case build
  case run
  case archive
}

enum HookPhase {
  case pre
  case post
}

func runHookIfNeeded(config: SidekickConfig?, command: HookCommand, phase: HookPhase) throws {
  let hooks = hooksForCommand(config: config, command: command)
  let label = labelFor(command: command, phase: phase)
  switch phase {
  case .pre:
    try runHookSpecIfNeeded(hooks?.pre, label: label)
  case .post:
    try runHookSpecIfNeeded(hooks?.post, label: label)
  }
}

func runSetupJobIfNeeded(config: SidekickConfig) throws -> Bool {
  guard config.setupJobCompleted == false else { return false }
  guard let job = config.setupJob else { return false }

  try runHookSpecIfNeeded(job.pre, label: "setup-job-pre")
  try runHookSpecIfNeeded(job.post, label: "setup-job-post")
  return true
}

private func hooksForCommand(config: SidekickConfig?, command: HookCommand) -> CommandHooks? {
  switch command {
  case .build:
    return config?.hooks?.build
  case .run:
    return config?.hooks?.run
  case .archive:
    return config?.hooks?.archive
  }
}

private func resolveHookExecutable(command: String, args: [String]) -> (String, [String]) {
  if command.contains("/") {
    return (command, args)
  }
  return ("/usr/bin/env", [command] + args)
}

private func runHookSpecIfNeeded(_ spec: CommandSpec?, label: String) throws {
  guard let spec else { return }
  let commandText = spec.command.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !commandText.isEmpty else {
    print("⚠️  \(label) hook has an empty command; skipping.")
    return
  }

  let args = spec.args ?? []
  let (executable, arguments) = resolveHookExecutable(command: commandText, args: args)
  let display = ([commandText] + args).joined(separator: " ")

  print("🧰 Running \(label) hook: \(display)")
  let result = try runProcessStreaming(executable: executable, arguments: arguments)
  if result.exitCode != 0 {
    print("❌ \(label) hook failed with exit code \(result.exitCode)")
    throw ExitCode(result.exitCode)
  }
}

private func labelFor(command: HookCommand, phase: HookPhase) -> String {
  let prefix: String
  switch phase {
  case .pre:
    prefix = "pre"
  case .post:
    prefix = "post"
  }

  switch command {
  case .build:
    return "\(prefix)-build"
  case .run:
    return "\(prefix)-run"
  case .archive:
    return "\(prefix)-archive"
  }
}
