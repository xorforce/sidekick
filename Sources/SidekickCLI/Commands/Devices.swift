import ArgumentParser
import Foundation

extension Sidekick {
  struct Devices: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List physical devices known to Xcode"
    )

    func run() throws {
      do {
        let devices = try withSpinner(message: "Fetching devices") {
          try fetchPhysicalDevices()
        }
        if devices.isEmpty {
          print("No devices found.")
          return
        }

        let sorted = devices.sorted { lhs, rhs in
          let la = lhs.available ?? false
          let ra = rhs.available ?? false
          if la != ra { return la && !ra }
          return (lhs.name ?? "").localizedCaseInsensitiveCompare(rhs.name ?? "") == .orderedAscending
        }

        for device in sorted {
          let formatted = formatDeviceDisplay(device)
          print("- \(formatted)")
        }
      } catch {
        print("Failed to list devices: \(error)")
        throw ExitCode.failure
      }
    }
  }
}

private func formatDeviceDisplay(_ device: PhysicalDevice) -> String {
  let name = device.name ?? "Unknown"
  let platform = formatPlatform(device.platform ?? "unknown")
  let osVersion = formatOSVersion(device.osVersion ?? "unknown")
  let id = device.identifier ?? "-"
  
  // Format: "Name - Platform Version - ID" or "Name - Platform - ID" if no version
  if osVersion.isEmpty {
    return "\(name) - \(platform) - \(id)"
  } else {
    return "\(name) - \(platform) \(osVersion) - \(id)"
  }
}

private func formatPlatform(_ platform: String) -> String {
  if platform.contains("iphoneos") || platform.contains("iphone") {
    return "iOS"
  } else if platform.contains("ipados") || platform.contains("ipad") {
    return "iPadOS"
  } else if platform.contains("macos") || platform.contains("mac") {
    return "macOS"
  } else if platform.contains("watchos") || platform.contains("watch") {
    return "watchOS"
  } else if platform.contains("tvos") || platform.contains("tv") {
    return "tvOS"
  } else if platform.contains("visionos") || platform.contains("vision") {
    return "visionOS"
  }
  return platform
}

private func formatOSVersion(_ osVersion: String) -> String {
  // Return the actual OS version, or empty string if unknown
  if osVersion == "unknown" || osVersion.isEmpty {
    return ""
  }
  return osVersion
}
