import ArgumentParser

enum Platform: String, ExpressibleByArgument, CaseIterable, Codable {
  case iosSim = "ios-sim"
  case iosDevice = "ios-device"
  case macos = "macos"
}

