import Foundation

enum XcodebuildAction: String {
  case build
  case test
}

struct XcodebuildOptions {
  let workspace: String?
  let project: String?
  let scheme: String
  let configuration: String
  let platform: Platform?
  let clean: Bool
  let testPlan: String?
}

func makeXcodebuildArguments(options: XcodebuildOptions, action: XcodebuildAction) -> [String] {
  var args: [String] = []
  args.append(contentsOf: projectSelectorArgs(options: options))
  args.append(contentsOf: ["-scheme", options.scheme])
  args.append(contentsOf: ["-configuration", options.configuration])
  args.append(contentsOf: platformArgs(platform: options.platform))

  if action == .test, let testPlan = options.testPlan, !testPlan.isEmpty {
    args.append(contentsOf: ["-testPlan", testPlan])
  }

  if options.clean {
    args.append("clean")
  }

  args.append(action.rawValue)
  return args
}

private func projectSelectorArgs(options: XcodebuildOptions) -> [String] {
  if let workspace = options.workspace {
    return ["-workspace", workspace]
  }
  if let project = options.project {
    return ["-project", project]
  }
  return []
}

private func platformArgs(platform: Platform?) -> [String] {
  switch platform {
  case .iosSim:
    return ["-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator"]
  case .iosDevice:
    return ["-sdk", "iphoneos", "-destination", "generic/platform=iOS"]
  case .macos:
    return ["-sdk", "macosx", "-destination", "platform=macOS"]
  case .none:
    return []
  }
}

