import ArgumentParser
import Foundation

extension Sidekick {
  struct Sim: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "List available simulators"
    )

    func run() throws {
      do {
        let groups = try fetchSimulators()
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

