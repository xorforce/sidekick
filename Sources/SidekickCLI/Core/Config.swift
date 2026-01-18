import Foundation

struct CommandSpec: Codable {
  var command: String
  var args: [String]?
}

struct CommandHooks: Codable {
  var pre: CommandSpec?
  var post: CommandSpec?
}

struct CommandHookConfig: Codable {
  var build: CommandHooks?
  var run: CommandHooks?
  var archive: CommandHooks?
  var test: CommandHooks?
}

struct SidekickConfig: Codable {
  var workspace: String?
  var project: String?
  var scheme: String?
  var configuration: String?
  var platform: Platform?
  var derivedDataPath: String?
  var allowProvisioningUpdates: Bool = false
  var archiveOutputPath: String?
  var testPlanPath: String?
  var hooks: CommandHookConfig? = nil
  var setupJob: CommandHooks? = nil
  var setupJobCompleted: Bool = false

  // Defaults for future run/test commands.
  var simulatorName: String?
  var simulatorUDID: String?
  var deviceName: String?
  var deviceUDID: String?

  init(
    workspace: String? = nil,
    project: String? = nil,
    scheme: String? = nil,
    configuration: String? = nil,
    platform: Platform? = nil,
    derivedDataPath: String? = nil,
    allowProvisioningUpdates: Bool = false,
    archiveOutputPath: String? = nil,
    testPlanPath: String? = nil,
    hooks: CommandHookConfig? = nil,
    setupJob: CommandHooks? = nil,
    setupJobCompleted: Bool = false,
    simulatorName: String? = nil,
    simulatorUDID: String? = nil,
    deviceName: String? = nil,
    deviceUDID: String? = nil
  ) {
    self.workspace = workspace
    self.project = project
    self.scheme = scheme
    self.configuration = configuration
    self.platform = platform
    self.derivedDataPath = derivedDataPath
    self.allowProvisioningUpdates = allowProvisioningUpdates
    self.archiveOutputPath = archiveOutputPath
    self.testPlanPath = testPlanPath
    self.hooks = hooks
    self.setupJob = setupJob
    self.setupJobCompleted = setupJobCompleted
    self.simulatorName = simulatorName
    self.simulatorUDID = simulatorUDID
    self.deviceName = deviceName
    self.deviceUDID = deviceUDID
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
    project = try container.decodeIfPresent(String.self, forKey: .project)
    scheme = try container.decodeIfPresent(String.self, forKey: .scheme)
    configuration = try container.decodeIfPresent(String.self, forKey: .configuration)
    platform = try container.decodeIfPresent(Platform.self, forKey: .platform)
    derivedDataPath = try container.decodeIfPresent(String.self, forKey: .derivedDataPath)
    allowProvisioningUpdates = try container.decodeIfPresent(Bool.self, forKey: .allowProvisioningUpdates) ?? false
    archiveOutputPath = try container.decodeIfPresent(String.self, forKey: .archiveOutputPath)
    testPlanPath = try container.decodeIfPresent(String.self, forKey: .testPlanPath)
    hooks = try container.decodeIfPresent(CommandHookConfig.self, forKey: .hooks)
    setupJob = try container.decodeIfPresent(CommandHooks.self, forKey: .setupJob)
    setupJobCompleted = try container.decodeIfPresent(Bool.self, forKey: .setupJobCompleted) ?? false
    simulatorName = try container.decodeIfPresent(String.self, forKey: .simulatorName)
    simulatorUDID = try container.decodeIfPresent(String.self, forKey: .simulatorUDID)
    deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
    deviceUDID = try container.decodeIfPresent(String.self, forKey: .deviceUDID)
  }
}

func configFilePath(
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) -> URL {
  root.appendingPathComponent(".sidekick/config.json")
}

func loadConfigIfAvailable(
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) -> SidekickConfig? {
  let path = configFilePath(root: root)
  return loadConfigFromPath(path)
}

func loadConfigIfAvailable(
  configPath: String?,
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) -> SidekickConfig? {
  guard let configPath else {
    return loadConfigIfAvailable(root: root)
  }

  let expandedPath = NSString(string: configPath).expandingTildeInPath
  let resolvedURL = URL(fileURLWithPath: expandedPath, relativeTo: root).standardizedFileURL
  if !FileManager.default.fileExists(atPath: resolvedURL.path) {
    print("Warning: config not found at \(resolvedURL.path)")
    return nil
  }

  return loadConfigFromPath(resolvedURL)
}

private func loadConfigFromPath(_ path: URL) -> SidekickConfig? {
  guard FileManager.default.fileExists(atPath: path.path) else {
    return nil
  }

  do {
    let data = try Data(contentsOf: path)
    return try JSONDecoder().decode(SidekickConfig.self, from: data)
  } catch {
    print("Warning: failed to load config at \(path.path): \(error)")
    return nil
  }
}

func saveConfig(
  _ config: SidekickConfig,
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) throws {
  let path = configFilePath(root: root)
  try FileManager.default.createDirectory(
    at: path.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let data = try encoder.encode(config)
  try data.write(to: path, options: .atomic)
}

func configDirectoryPath(
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) -> URL {
  root.appendingPathComponent(".sidekick/configs", isDirectory: true)
}

func namedConfigPath(
  name: String,
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) -> URL {
  configDirectoryPath(root: root).appendingPathComponent("\(name).json")
}

func listConfigNames(
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) -> [String] {
  let directory = configDirectoryPath(root: root)
  guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
    return []
  }

  return entries
    .filter { $0.pathExtension == "json" }
    .map { $0.deletingPathExtension().lastPathComponent }
    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

func loadNamedConfig(
  name: String,
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) -> SidekickConfig? {
  let path = namedConfigPath(name: name, root: root)
  return loadConfigFromPath(path)
}

func saveNamedConfig(
  _ config: SidekickConfig,
  name: String,
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) throws {
  let directory = configDirectoryPath(root: root)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

  let path = namedConfigPath(name: name, root: root)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let data = try encoder.encode(config)
  try data.write(to: path, options: .atomic)
}

func defaultConfigNamePath(
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) -> URL {
  root.appendingPathComponent(".sidekick/default-config")
}

func readDefaultConfigName(
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) -> String? {
  let path = defaultConfigNamePath(root: root)
  guard let data = try? Data(contentsOf: path) else {
    return nil
  }
  let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  return name.isEmpty ? nil : name
}

func writeDefaultConfigName(
  _ name: String,
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) throws {
  let path = defaultConfigNamePath(root: root)
  try FileManager.default.createDirectory(
    at: path.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  let data = Data(name.utf8)
  try data.write(to: path, options: .atomic)
}

func setDefaultConfig(
  name: String,
  root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
) throws {
  let namedPath = namedConfigPath(name: name, root: root)
  guard FileManager.default.fileExists(atPath: namedPath.path) else {
    throw NSError(domain: "SidekickConfig", code: 1, userInfo: [
      NSLocalizedDescriptionKey: "Config '\(name)' not found at \(namedPath.path)"
    ])
  }

  let defaultPath = configFilePath(root: root)
  try FileManager.default.createDirectory(
    at: defaultPath.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  if FileManager.default.fileExists(atPath: defaultPath.path) {
    try FileManager.default.removeItem(at: defaultPath)
  }
  try FileManager.default.copyItem(at: namedPath, to: defaultPath)
  try writeDefaultConfigName(name, root: root)
}

