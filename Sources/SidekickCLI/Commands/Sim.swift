import ArgumentParser
import Foundation

extension Sidekick {
  struct Sim: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List available simulators"
    )

    func run() throws {
      do {
        let groups = try withSpinner(message: "Fetching simulators") {
          try fetchSimulators()
        }
        if groups.isEmpty {
          print("No available simulators found.")
          return
        }

        for group in groups {
          print(prettifyRuntime(group.runtime))
          for device in group.devices {
            let state = device.state ?? "unknown"
            print("  - \(device.name) [\(state)] (\(device.udid))")
          }
          print("")
        }
      } catch {
        print("Failed to list simulators: \(error)")
        throw ExitCode.failure
      }
    }
  }
}

private func prettifyRuntime(_ runtimeKey: String) -> String {
  var s = runtimeKey
  s = s.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
  s = s.replacingOccurrences(of: "iOS-", with: "iOS ")
  s = s.replacingOccurrences(of: "tvOS-", with: "tvOS ")
  s = s.replacingOccurrences(of: "watchOS-", with: "watchOS ")
  s = s.replacingOccurrences(of: "visionOS-", with: "visionOS ")
  s = s.replacingOccurrences(of: "-", with: ".")
  return s
}

private func formatRuntimeForDisplay(_ runtimeKey: String) -> String {
  var s = runtimeKey
  s = s.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
  
  // Extract platform and version
  if s.hasPrefix("iOS-") {
    let version = String(s.dropFirst(4)).replacingOccurrences(of: "-", with: ".")
    return "iOS \(version)"
  } else if s.hasPrefix("tvOS-") {
    let version = String(s.dropFirst(5)).replacingOccurrences(of: "-", with: ".")
    return "tvOS \(version)"
  } else if s.hasPrefix("watchOS-") {
    let version = String(s.dropFirst(8)).replacingOccurrences(of: "-", with: ".")
    return "watchOS \(version)"
  } else if s.hasPrefix("visionOS-") {
    let version = String(s.dropFirst(9)).replacingOccurrences(of: "-", with: ".")
    return "visionOS \(version)"
  } else if s.hasPrefix("macOS-") {
    let version = String(s.dropFirst(6)).replacingOccurrences(of: "-", with: ".")
    return "macOS \(version)"
  }
  
  // Fallback to original prettify logic
  return prettifyRuntime(runtimeKey)
}

private enum DeviceType: String, CaseIterable {
  case iPhone = "iPhone"
  case iPad = "iPad"
  case Mac = "Mac"
  case AppleWatch = "Apple Watch"
  case AppleTV = "Apple TV"
  case VisionPro = "Apple Vision Pro"
  case other = "Other"
  
  static func from(deviceName: String) -> DeviceType {
    let name = deviceName.lowercased()
    if name.contains("iphone") {
      return .iPhone
    } else if name.contains("ipad") {
      return .iPad
    } else if name.contains("mac") || name.contains("imac") || name.contains("macbook") || name.contains("mac mini") || name.contains("mac pro") || name.contains("mac studio") {
      return .Mac
    } else if name.contains("watch") {
      return .AppleWatch
    } else if name.contains("tv") || name.contains("appletv") {
      return .AppleTV
    } else if name.contains("vision") {
      return .VisionPro
    }
    return .other
  }
}

private struct DeviceGroup {
  let type: DeviceType
  let devices: [(runtime: String, device: SimulatorDevice)]
}

private func groupDevicesByType(_ groups: [SimulatorRuntimeGroup]) -> [DeviceGroup] {
  var deviceGroups: [DeviceType: [(runtime: String, device: SimulatorDevice)]] = [:]
  
  for group in groups {
    for device in group.devices {
      let deviceType = DeviceType.from(deviceName: device.name)
      if deviceGroups[deviceType] == nil {
        deviceGroups[deviceType] = []
      }
      deviceGroups[deviceType]?.append((runtime: group.runtime, device: device))
    }
  }
  
  // Sort by device type order, then by device name
  return DeviceType.allCases.compactMap { type in
    guard let devices = deviceGroups[type], !devices.isEmpty else { return nil }
    let sorted = devices.sorted { lhs, rhs in
      lhs.device.name.localizedCaseInsensitiveCompare(rhs.device.name) == .orderedAscending
    }
    return DeviceGroup(type: type, devices: sorted)
  }
}
