import Foundation

func printLogs(logPaths: LogPaths, prettyIncluded: Bool) {
  print("\nLogs saved to:")
  print("  Raw: \(logPaths.rawLogURL.path)")
  if prettyIncluded {
    print("  Pretty: \(logPaths.prettyLogURL.path)")
  } else {
    print("  Pretty (fallback to raw): \(logPaths.prettyLogURL.path)")
  }
}

func printErrors(_ errors: [String]) {
  guard !errors.isEmpty else { return }
  print("\nErrors:")
  errors.forEach { print("  \($0)") }
}

