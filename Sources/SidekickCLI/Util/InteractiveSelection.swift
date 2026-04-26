import Foundation

#if canImport(Darwin)
import Darwin.C
#elseif canImport(Glibc)
import Glibc
#endif

enum TerminalKey {
  case up
  case down
  case enter
  case escape
  case backspace
  case other(Character)
}

private struct ANSICodes {
  static let reset = "\u{1B}[0m"
  static let bold = "\u{1B}[1m"
  static let cyan = "\u{1B}[36m"
  static let brightCyan = "\u{1B}[96m"
  static let green = "\u{1B}[32m"
}

struct InteractiveSelection {
  private static let maxVisibleOptions = 10

  static func select(
    prompt: String,
    options: [String],
    allowSkip: Bool = false
  ) -> String? {
    guard !options.isEmpty else { return nil }
    guard options.count > 1 else { return options.first }
    
    let terminal = TerminalController()
    defer { terminal.restore() }
    
    var query = ""
    var filteredOptions = options
    var selectedIndex = 0
    var isFirstRender = true
    var lastRenderLineCount = 0

    func updateFilteredOptions(resetSelection: Bool) {
      filteredOptions = filteredList(from: options, matching: query)
      if filteredOptions.isEmpty {
        selectedIndex = allowSkip ? -1 : 0
        return
      }
      if resetSelection || selectedIndex >= filteredOptions.count {
        selectedIndex = 0
      }
    }

    func render() {
      if !isFirstRender {
        terminal.clearLines(count: lastRenderLineCount)
      } else {
        isFirstRender = false
      }

      print("\(prompt):")
      print("(Type to filter, ↑/↓ to navigate, Enter to select\(allowSkip ? ", Esc to skip" : ""))")
      print("Filter: \(query.isEmpty ? "-" : query)")
      print()

      var lineCount = 4
      lineCount += renderSkipRow(selectedIndex: selectedIndex, allowSkip: allowSkip)
      lineCount += renderVisibleOptions(filteredOptions, selectedIndex: selectedIndex, query: query)
      lineCount += renderFilterSummary(options: options, filteredOptions: filteredOptions, query: query)
      lastRenderLineCount = lineCount
    }

    updateFilteredOptions(resetSelection: true)
    render()

    while true {
      guard let key = terminal.readKey() else { continue }

      switch key {
      case .up:
        selectedIndex = previousSelection(
          current: selectedIndex,
          optionCount: filteredOptions.count,
          allowSkip: allowSkip
        )
        render()

      case .down:
        selectedIndex = nextSelection(
          current: selectedIndex,
          optionCount: filteredOptions.count,
          allowSkip: allowSkip
        )
        render()

      case .enter:
        terminal.clearLines(count: lastRenderLineCount)
        if allowSkip && selectedIndex == -1 {
          print("\(prompt): Skipped")
          print()
          return nil
        }
        guard !filteredOptions.isEmpty, filteredOptions.indices.contains(selectedIndex) else {
          render()
          continue
        }
        let selected = filteredOptions[selectedIndex]
        print("\(prompt): \(selected)")
        print()
        return selected

      case .escape:
        if allowSkip {
          return nil
        }
        return options.first

      case .backspace:
        guard !query.isEmpty else { continue }
        query.removeLast()
        updateFilteredOptions(resetSelection: true)
        render()

      case .other(let char):
        guard shouldAppendToQuery(char) else { continue }
        query.append(char)
        updateFilteredOptions(resetSelection: true)
        render()
      }
    }
  }

  private static func filteredList(from options: [String], matching query: String) -> [String] {
    guard !query.isEmpty else { return options }
    return options.filter { option in
      option.localizedCaseInsensitiveContains(query)
    }
  }

  private static func renderSkipRow(selectedIndex: Int, allowSkip: Bool) -> Int {
    guard allowSkip else { return 0 }
    if selectedIndex == -1 {
      print("\(ANSICodes.brightCyan)\(ANSICodes.bold)→ [Skip]\(ANSICodes.reset)")
      return 1
    }
    print("  [Skip]")
    return 1
  }

  private static func renderVisibleOptions(_ options: [String], selectedIndex: Int, query: String) -> Int {
    guard !options.isEmpty else {
      print("  No matches for \"\(query)\"")
      return 1
    }

    let window = visibleWindow(selectedIndex: selectedIndex, optionCount: options.count)
    for index in window {
      let marker = index == selectedIndex ? "→" : " "
      let prefix = index == selectedIndex ? "\(ANSICodes.brightCyan)\(ANSICodes.bold)\(marker)" : " \(marker)"
      let suffix = index == selectedIndex ? ANSICodes.reset : ""
      print("\(prefix) [\(index + 1)] \(options[index])\(suffix)")
    }
    return window.count
  }

  private static func renderFilterSummary(options: [String], filteredOptions: [String], query: String) -> Int {
    guard options.count > maxVisibleOptions || !query.isEmpty else { return 0 }
    let count = filteredOptions.count
    let label = query.isEmpty ? "Showing first \(min(count, maxVisibleOptions)) of \(count)" : "\(count) match\(count == 1 ? "" : "es")"
    print()
    print(label)
    return 2
  }

  private static func visibleWindow(selectedIndex: Int, optionCount: Int) -> Range<Int> {
    guard optionCount > maxVisibleOptions, selectedIndex >= 0 else {
      return 0..<min(optionCount, maxVisibleOptions)
    }
    let halfWindow = maxVisibleOptions / 2
    var start = max(0, selectedIndex - halfWindow)
    let maxStart = max(0, optionCount - maxVisibleOptions)
    start = min(start, maxStart)
    return start..<min(start + maxVisibleOptions, optionCount)
  }

  private static func previousSelection(current: Int, optionCount: Int, allowSkip: Bool) -> Int {
    guard optionCount > 0 else { return allowSkip ? -1 : 0 }
    if allowSkip && current == 0 { return -1 }
    if current == -1 { return optionCount - 1 }
    return max(0, current - 1)
  }

  private static func nextSelection(current: Int, optionCount: Int, allowSkip: Bool) -> Int {
    guard optionCount > 0 else { return allowSkip ? -1 : 0 }
    if allowSkip && current == -1 { return 0 }
    if current < optionCount - 1 { return current + 1 }
    return allowSkip ? -1 : optionCount - 1
  }

  private static func shouldAppendToQuery(_ char: Character) -> Bool {
    char.isLetter || char.isNumber || char == " " || char == "-" || char == "_" || char == "."
  }
}

private class TerminalController {
  private var originalTermios: termios?
  private var isRawMode = false
  
  init() {
    enableRawMode()
  }
  
  deinit {
    restore()
  }
  
  func restore() {
    disableRawMode()
  }
  
  private func enableRawMode() {
    var term = termios()
    tcgetattr(STDIN_FILENO, &term)
    originalTermios = term
    
    // Disable canonical mode and echo
    term.c_lflag &= ~(UInt(ECHO | ICANON))
    tcsetattr(STDIN_FILENO, TCSANOW, &term)
    isRawMode = true
  }
  
  private func disableRawMode() {
    guard let original = originalTermios, isRawMode else { return }
    var term = original
    tcsetattr(STDIN_FILENO, TCSANOW, &term)
    isRawMode = false
  }
  
  func readKey() -> TerminalKey? {
    var char: UInt8 = 0
    let bytesRead = read(STDIN_FILENO, &char, 1)
    
    guard bytesRead == 1 else { return nil }
    
    // Check for escape sequence (arrow keys)
    if char == 0x1B { // ESC
      // Try to read the next character immediately
      var nextChar: UInt8 = 0
      let nextRead = read(STDIN_FILENO, &nextChar, 1)
      
      if nextRead == 1 && nextChar == 0x5B { // [
        // Read the arrow key character
        var arrowChar: UInt8 = 0
        if read(STDIN_FILENO, &arrowChar, 1) == 1 {
          switch arrowChar {
          case 0x41: // A - Up arrow
            return .up
          case 0x42: // B - Down arrow
            return .down
          case 0x43: // C - Right arrow (not used)
            return .escape
          case 0x44: // D - Left arrow (not used)
            return .escape
          default:
            return .escape
          }
        }
      }
      return .escape
    }
    
    // Handle regular characters
    if char == 13 || char == 10 { // Enter/Return
      return .enter
    }

    if char == 0x7F || char == 0x08 { // Delete/Backspace
      return .backspace
    }

    let scalar = UnicodeScalar(char)
    if scalar.isASCII {
      return .other(Character(scalar))
    }
    
    return nil
  }
  
  func clearLines(count: Int) {
    // Move cursor up by count lines and clear each
    for _ in 0..<count {
      print("\u{1B}[1A\u{1B}[K", terminator: "")
    }
    // Ensure output is flushed
    fflush(stdout)
  }
}
