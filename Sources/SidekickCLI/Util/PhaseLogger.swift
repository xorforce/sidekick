import Foundation

struct PhaseLogger {
  private var currentHeading: String?

  mutating func heading(_ title: String) {
    guard currentHeading != title else { return }
    if currentHeading != nil {
      print()
    }
    currentHeading = title
    print("== \(title) ==")
  }

  func detail(_ message: String) {
    print("- \(message)")
  }

  func path(_ label: String, value: String) {
    print("- \(label): \(value)")
  }
}
