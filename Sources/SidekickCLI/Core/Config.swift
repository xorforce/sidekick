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

