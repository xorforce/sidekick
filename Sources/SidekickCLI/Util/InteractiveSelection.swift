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
  static func select(
    prompt: String,
    options: [String],
    allowSkip: Bool = false
  ) -> String? {
    guard !options.isEmpty else { return nil }
    guard options.count > 1 else { return options.first }
    
    let terminal = TerminalController()
    defer { terminal.restore() }
    
    var selectedIndex = 0
    let skipIndex = allowSkip ? -1 : nil
    let totalLines = options.count + (allowSkip ? 1 : 0) + 3 // +3 for prompt lines + blank line
    var isFirstRender = true
    
    func render() {
      if !isFirstRender {
        // Clear previous rendering (options + prompt lines)
        terminal.clearLines(count: totalLines)
      } else {
        isFirstRender = false
      }
      
      // Display prompt
      print("\(prompt):")
      print("(Use ↑/↓ to navigate, Enter to select\(allowSkip ? ", Esc to skip" : ""))")
      print() // Blank line for spacing
      
      // Display options
      if allowSkip {
        if skipIndex == selectedIndex {
          print("\(ANSICodes.brightCyan)\(ANSICodes.bold)→ [Skip]\(ANSICodes.reset)")
        } else {
          print("  [Skip]")
        }
      }
      
      for (index, option) in options.enumerated() {
        if index == selectedIndex {
          print("\(ANSICodes.brightCyan)\(ANSICodes.bold)→ [\(index + 1)] \(option)\(ANSICodes.reset)")
        } else {
          print("  [\(index + 1)] \(option)")
        }
      }
    }
    
    render()
    
    while true {
      guard let key = terminal.readKey() else { continue }
      
      switch key {
      case .up:
        if allowSkip && selectedIndex == 0 {
          selectedIndex = skipIndex!
        } else if selectedIndex > 0 {
          selectedIndex -= 1
        } else if allowSkip {
          selectedIndex = options.count - 1
        }
        render()
        
      case .down:
        if allowSkip && selectedIndex == skipIndex {
          selectedIndex = 0
        } else if selectedIndex < options.count - 1 {
          selectedIndex += 1
        } else if allowSkip {
          selectedIndex = skipIndex!
        }
        render()
        
      case .enter:
        // Clear the selection display and print final choice
        terminal.clearLines(count: totalLines)
        if allowSkip && selectedIndex == skipIndex {
          print("\(prompt): Skipped")
          print() // Blank line for spacing
          return nil
        }
        let selected = options[selectedIndex]
        print("\(prompt): \(selected)")
        print() // Blank line for spacing
        return selected
        
      case .escape:
        if allowSkip {
          return nil
        }
        // If skip not allowed, treat escape as cancel and return first option
        return options.first
        
      case .other(let char):
        // Handle numeric input (1-9)
        if let num = Int(String(char)), num >= 1, num <= options.count {
          selectedIndex = num - 1
          render()
        } else if allowSkip && char == "0" {
          selectedIndex = skipIndex!
          render()
        }
      }
    }
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
    
    if char == 27 { // ESC
      return .escape
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
