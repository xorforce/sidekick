import Foundation

struct RunTarget {
  let name: String
  let udid: String
  let isDevice: Bool

  var displayName: String {
    let type = isDevice ? "Device" : "Simulator"
    return "\(name) (\(type))"
  }
}

struct BuildOutput {
  let stdout: String
  let stderr: String
}

enum RunError: Error, CustomStringConvertible {
  case noTargetAvailable
  case failedToGetBuildSettings(String)
  case missingBuildSettings
  case appBundleNotFound(String)
  case infoPlistNotFound(String)
  case failedToExtractBundleId(String)
  case installFailed(String)
  case launchFailed(String)

  var description: String {
    switch self {
    case .noTargetAvailable:
      return "No device or simulator available. Run 'sidekick configure --init' to configure."
    case .failedToGetBuildSettings(let error):
      return "Failed to get build settings: \(error)"
    case .missingBuildSettings:
      return "Could not find BUILT_PRODUCTS_DIR or FULL_PRODUCT_NAME in build settings"
    case .appBundleNotFound(let path):
      return "App bundle not found at: \(path)"
    case .infoPlistNotFound(let path):
      return "Info.plist not found at: \(path)"
    case .failedToExtractBundleId(let error):
      return "Failed to extract bundle identifier: \(error)"
    case .installFailed(let error):
      return "Failed to install app: \(error)"
    case .launchFailed(let error):
      return "Failed to launch app: \(error)"
    }
  }
}

func determineRunTarget(config: SidekickConfig?, forceSimulator: Bool) throws -> RunTarget {
  if forceSimulator {
    print("⏭️ Simulator mode forced via --simulator flag")
  }

  if !forceSimulator {
    if let deviceUDID = config?.deviceUDID, !deviceUDID.isEmpty,
       let deviceName = config?.deviceName {
      print("   Device configured: \(deviceName)")

      let isConnected = withSpinner(message: "Checking if device is connected via USB") {
        isDeviceConnectedViaUSB(udid: deviceUDID)
      }

      if isConnected {
        print("   ✓ Device is connected via USB!")
        return RunTarget(name: deviceName, udid: deviceUDID, isDevice: true)
      } else {
        print("   ⚠️  Device '\(deviceName)' is not connected via USB (or is localNetwork)")
        print("   Falling back to simulator...")
      }
    } else {
      print("   No device configured")
    }
  }

  if let simulatorUDID = config?.simulatorUDID, !simulatorUDID.isEmpty,
     let simulatorName = config?.simulatorName {
    print("   ✓ Using configured simulator: \(simulatorName)")
    return RunTarget(name: simulatorName, udid: simulatorUDID, isDevice: false)
  }

  print("   No simulator configured, searching for available iPhone...")

  let simulator = try? withSpinner(message: "Searching for available iPhone simulator") {
    try findAnyIPhoneSimulator()
  }

  if let sim = simulator {
    print("   ✓ Found: \(sim.name)")
    return RunTarget(name: sim.name, udid: sim.udid, isDevice: false)
  }

  throw RunError.noTargetAvailable
}

func findAnyIPhoneSimulator() throws -> SimulatorDevice? {
  let groups = try fetchSimulators()

  for group in groups {
    if let booted = group.devices.first(where: {
      $0.name.lowercased().contains("iphone") && $0.state == "Booted"
    }) {
      return booted
    }
  }

  let sortedGroups = groups.sorted { $0.runtime > $1.runtime }
  for group in sortedGroups {
    if let device = group.devices.first(where: { $0.name.lowercased().contains("iphone") }) {
      return device
    }
  }

  return nil
}

func extractBuildErrors(from output: String) -> [String] {
  let pattern = #"error:\s*(.+)"#
  guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
    return []
  }

  let range = NSRange(location: 0, length: output.utf16.count)
  let matches = regex.matches(in: output, options: [], range: range)

  var errors: [String] = []
  for match in matches {
    guard let range = Range(match.range(at: 1), in: output) else { continue }
    let message = output[range].trimmingCharacters(in: .whitespacesAndNewlines)
    let full = "error: \(message)"
    if !errors.contains(full) { errors.append(full) }
  }
  return errors
}

