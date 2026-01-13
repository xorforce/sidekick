import Foundation

func chooseProject(from entries: [ProjectEntry], nonInteractive: Bool) -> ProjectEntry {
  guard entries.count > 1, !nonInteractive else {
    return entries.first!
  }

  print("Select workspace/project:")
  for (index, entry) in entries.enumerated() {
    print("  [\(index + 1)] \(entry.displayName)")
  }
  print("Enter choice (1-\(entries.count)) [1]: ", terminator: "")

  if let input = readLine(),
     let choice = Int(input.trimmingCharacters(in: .whitespaces)),
     choice >= 1, choice <= entries.count {
    return entries[choice - 1]
  }

  return entries.first!
}

func chooseOption(prompt: String, options: [String], nonInteractive: Bool) -> String? {
  guard !options.isEmpty else { return nil }
  guard options.count > 1, !nonInteractive else {
    return options.first
  }

  print("\(prompt):")
  for (index, option) in options.enumerated() {
    print("  [\(index + 1)] \(option)")
  }
  print("Enter choice (1-\(options.count)) [1]: ", terminator: "")

  if let input = readLine(),
     let choice = Int(input.trimmingCharacters(in: .whitespaces)),
     choice >= 1, choice <= options.count {
    return options[choice - 1]
  }

  return options.first
}

