import Foundation

struct SidekickConfig: Codable {
  var workspace: String?
  var project: String?
  var scheme: String?
  var configuration: String?
  var platform: Platform?
  var derivedDataPath: String?

  // Defaults for future run/test commands.
  var simulatorName: String?
  var simulatorUDID: String?
  var deviceName: String?
  var deviceUDID: String?
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

