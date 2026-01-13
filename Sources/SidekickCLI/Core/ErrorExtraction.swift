import Foundation

func extractErrors(from output: String) -> [String] {
  let pattern = #"error:\s*(.+)"#
  guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
    return []
  }

  let range = NSRange(location: 0, length: output.utf16.count)
  let matches = regex.matches(in: output, options: [], range: range)

  var errors: [String] = []
  for match in matches {
    guard let captureRange = Range(match.range(at: 1), in: output) else { continue }
    let message = output[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = dropLeadingErrorPrefix(message)
    let full = "error: \(normalized)"
    if !errors.contains(full) {
      errors.append(full)
    }
  }
  return errors
}

private func dropLeadingErrorPrefix(_ message: String) -> String {
  let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.lowercased().hasPrefix("error:") {
    return trimmed.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  return trimmed
}

