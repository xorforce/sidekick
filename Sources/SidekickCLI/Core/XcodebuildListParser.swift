import Foundation

func parseXcodebuildListSection(output: String, section: String) -> [String] {
  var values: [String] = []
  var inSection = false

  for rawLine in output.split(separator: "\n") {
    let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { continue }

    if trimmed.hasPrefix(section + ":") {
      inSection = true
      continue
    }

    if inSection {
      if trimmed.hasSuffix(":") { break }
      values.append(trimmed)
    }
  }

  return values
}

