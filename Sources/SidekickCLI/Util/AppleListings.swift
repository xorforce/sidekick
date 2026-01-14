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

// MARK: - devicectl parsing (preferred for detecting USB vs local network)

private struct DevicectlListResponse: Codable {
  let result: DevicectlListResult?
}

private struct DevicectlListResult: Codable {
  let devices: [DevicectlDevice]?
}

private struct DevicectlDevice: Codable {
  let connectionProperties: DevicectlConnectionProperties?
  let deviceProperties: DevicectlDeviceProperties?
  let hardwareProperties: DevicectlHardwareProperties?
}

private struct DevicectlConnectionProperties: Codable {
  let transportType: String?
  let tunnelState: String?
}

private struct DevicectlDeviceProperties: Codable {
  let name: String?
  let osVersionNumber: String?
}

private struct DevicectlHardwareProperties: Codable {
  let platform: String?
  let reality: String?
  let udid: String?
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

func fetchUSBConnectedDevices() throws -> [PhysicalDevice] {
  // Preferred: devicectl gives us transportType so we can ignore local-network pairing,
  // and we can probe connectivity by querying lockState.
  if let devices = try? fetchUSBConnectedDevicesFromDevicectl() {
    return devices
  }

  // Fallback: best-effort heuristics from xcdevice output.
  let devices = try fetchPhysicalDevices()
  return devices.filter {
    let iface = ($0.interface ?? "").lowercased()
    let isUsb = iface == "usb"
      || iface == "wired"
      || iface == "wired-or-wireless"
      || iface == "wired or wireless"
    return ($0.available ?? false) && isUsb
  }
}

private func fetchUSBConnectedDevicesFromDevicectl() throws -> [PhysicalDevice] {
  let tmpURL = TempFileManager.shared.makeTempFileURL(
    prefix: "sidekick-devicectl-devices",
    fileExtension: "json"
  )
  defer { TempFileManager.shared.remove(tmpURL) }

  let result = try runProcess(
    executable: "/usr/bin/xcrun",
    arguments: ["devicectl", "list", "devices", "--json-output", tmpURL.path]
  )

  guard result.exitCode == 0 else {
    throw AppleToolingError.toolFailed(tool: "xcrun devicectl list devices", exitCode: result.exitCode, stderr: result.stderr)
  }

  let data = try Data(contentsOf: tmpURL)
  let decoded = try JSONDecoder().decode(DevicectlListResponse.self, from: data)
  let devices = decoded.result?.devices ?? []

  // First filter: only physical, non-localNetwork devices.
  let candidates: [PhysicalDevice] = devices.compactMap { device in
    guard let udid = device.hardwareProperties?.udid else { return nil }

    // Only consider physical devices
    if let reality = device.hardwareProperties?.reality?.lowercased(), reality != "physical" {
      return nil
    }

    // Ignore network devices for now (Wi-Fi pairing).
    let transport = device.connectionProperties?.transportType?.lowercased()
    if transport == "localnetwork" {
      return nil
    }

    return PhysicalDevice(
      name: device.deviceProperties?.name,
      identifier: udid,
      platform: device.hardwareProperties?.platform,
      osVersion: device.deviceProperties?.osVersionNumber,
      interface: device.connectionProperties?.transportType,
      available: true,
      simulator: false
    )
  }

  // Second filter: probe connectivity (paired-but-not-connected devices can show up here).
  return candidates.filter { candidate in
    guard let udid = candidate.identifier else { return false }
    return (try? probeDeviceLockState(udid: udid)) ?? false
  }
}

private func probeDeviceLockState(udid: String) throws -> Bool {
  let tmpURL = TempFileManager.shared.makeTempFileURL(
    prefix: "sidekick-devicectl-lockstate",
    fileExtension: "json"
  )
  defer { TempFileManager.shared.remove(tmpURL) }

  let result = try runProcess(
    executable: "/usr/bin/xcrun",
    arguments: [
      "devicectl", "device", "info", "lockState",
      "--device", udid,
      "--timeout", "5",
      "--json-output", tmpURL.path
    ]
  )

  // If devicectl can’t reach the device, it should fail non-zero.
  return result.exitCode == 0
}

/// Check whether a particular UDID is *currently* connected via USB.
/// - Returns: false for localNetwork devices, or if devicectl cannot reach it.
func isDeviceConnectedViaUSB(udid: String) -> Bool {
  // Ignore local network pairing.
  if let transport = try? fetchDevicectlTransportType(udid: udid),
     transport.lowercased() == "localnetwork" {
    return false
  }
  return (try? probeDeviceLockState(udid: udid)) ?? false
}

private func fetchDevicectlTransportType(udid: String) throws -> String {
  let tmpURL = TempFileManager.shared.makeTempFileURL(
    prefix: "sidekick-devicectl-devices",
    fileExtension: "json"
  )
  defer { TempFileManager.shared.remove(tmpURL) }

  let result = try runProcess(
    executable: "/usr/bin/xcrun",
    arguments: ["devicectl", "list", "devices", "--timeout", "5", "--json-output", tmpURL.path]
  )
  guard result.exitCode == 0 else {
    throw AppleToolingError.toolFailed(tool: "xcrun devicectl list devices", exitCode: result.exitCode, stderr: result.stderr)
  }

  let data = try Data(contentsOf: tmpURL)
  let decoded = try JSONDecoder().decode(DevicectlListResponse.self, from: data)
  let devices = decoded.result?.devices ?? []

  for device in devices {
    if device.hardwareProperties?.udid == udid {
      return device.connectionProperties?.transportType ?? ""
    }
  }

  return ""
}
