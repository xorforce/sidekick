import Foundation

enum AppleToolingError: Error, CustomStringConvertible {
  case toolFailed(tool: String, exitCode: Int32, stderr: String)
  case invalidOutput(tool: String, message: String)

  var description: String {
    switch self {
    case .toolFailed(let tool, let exitCode, let stderr):
      let cleaned = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      return "\(tool) failed (exit \(exitCode))\(cleaned.isEmpty ? "" : ": \(cleaned)")"
    case .invalidOutput(let tool, let message):
      return "\(tool) returned unexpected output: \(message)"
    }
  }
}

struct SimulatorDevice: Codable, Hashable {
  let name: String
  let udid: String
  let state: String?
  let isAvailable: Bool?
  let availabilityError: String?
}

struct SimulatorRuntimeGroup: Hashable {
  let runtime: String
  let devices: [SimulatorDevice]
}

private struct SimctlListResponse: Codable {
  let devices: [String: [SimulatorDevice]]
}

func fetchSimulators(includeUnavailable: Bool = false) throws -> [SimulatorRuntimeGroup] {
  let result = try runProcess(
    executable: "/usr/bin/xcrun",
    arguments: ["simctl", "list", "-j", "devices"]
  )

  guard result.exitCode == 0 else {
    throw AppleToolingError.toolFailed(tool: "xcrun simctl list", exitCode: result.exitCode, stderr: result.stderr)
  }

  guard let data = result.stdout.data(using: .utf8) else {
    throw AppleToolingError.invalidOutput(tool: "xcrun simctl list", message: "stdout was not UTF-8")
  }

  let decoded: SimctlListResponse
  do {
    decoded = try JSONDecoder().decode(SimctlListResponse.self, from: data)
  } catch {
    throw AppleToolingError.invalidOutput(tool: "xcrun simctl list", message: "failed to decode JSON: \(error)")
  }

  var groups: [SimulatorRuntimeGroup] = []
  for (runtime, devices) in decoded.devices {
    let filtered: [SimulatorDevice]
    if includeUnavailable {
      filtered = devices
    } else {
      filtered = devices.filter { ($0.isAvailable ?? true) && $0.availabilityError == nil }
    }

    if filtered.isEmpty { continue }
    groups.append(
      SimulatorRuntimeGroup(
        runtime: runtime,
        devices: filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
      )
    )
  }

  return groups.sorted { $0.runtime.localizedCaseInsensitiveCompare($1.runtime) == .orderedAscending }
}

struct PhysicalDevice: Codable, Hashable {
  let name: String?
  let identifier: String?
  let platform: String?
  let osVersion: String?
  let interface: String?
  let available: Bool?
  let simulator: Bool?
}

func fetchPhysicalDevices() throws -> [PhysicalDevice] {
  let result = try runProcess(
    executable: "/usr/bin/xcrun",
    arguments: ["xcdevice", "list", "--json"]
  )

  guard result.exitCode == 0 else {
    throw AppleToolingError.toolFailed(tool: "xcrun xcdevice list", exitCode: result.exitCode, stderr: result.stderr)
  }

  guard let data = result.stdout.data(using: .utf8) else {
    throw AppleToolingError.invalidOutput(tool: "xcrun xcdevice list", message: "stdout was not UTF-8")
  }

  let decoded: [PhysicalDevice]
  do {
    decoded = try JSONDecoder().decode([PhysicalDevice].self, from: data)
  } catch {
    throw AppleToolingError.invalidOutput(tool: "xcrun xcdevice list", message: "failed to decode JSON: \(error)")
  }

  return decoded
    .filter { ($0.simulator ?? false) == false }
    .sorted {
      ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
    }
}

func fetchConnectedPhysicalDevices() throws -> [PhysicalDevice] {
  try fetchPhysicalDevices().filter { $0.available ?? false }
}

