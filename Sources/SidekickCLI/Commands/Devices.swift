import ArgumentParser
import Foundation

extension Sidekick {
  struct Devices: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List physical devices known to Xcode"
    )

    func run() throws {
      do {
        let devices = try fetchPhysicalDevices()
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
          let name = device.name ?? "Unknown"
          let platform = device.platform ?? "unknown"
          let os = device.osVersion ?? "unknown"
          let id = device.identifier ?? "-"
          let status = (device.available ?? false) ? "connected" : "not connected"
          print("- \(name) — \(platform) \(os) — \(status) — \(id)")
        }
      } catch {
        print("Failed to list devices: \(error)")
        throw ExitCode.failure
      }
    }
  }
}

