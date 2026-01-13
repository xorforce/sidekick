import Foundation

#if canImport(Darwin)
import Darwin.C
#elseif canImport(Glibc)
import Glibc
#endif

class LoadingSpinner {
  private var isRunning = false
  private var spinnerThread: Thread?
  private let message: String
  private let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  private var currentFrameIndex = 0
  
  init(message: String) {
    self.message = message
  }
  
  func start() {
    guard !isRunning else { return }
    isRunning = true
    
    // Print initial spinner frame
    let frame = spinnerFrames[currentFrameIndex]
    print("\(frame) \(message)", terminator: "")
    fflush(stdout)
    currentFrameIndex = (currentFrameIndex + 1) % spinnerFrames.count
    
    spinnerThread = Thread {
      while self.isRunning {
        Thread.sleep(forTimeInterval: 0.1)
        if self.isRunning {
          let frame = self.spinnerFrames[self.currentFrameIndex]
          print("\r\(frame) \(self.message)", terminator: "")
          fflush(stdout)
          self.currentFrameIndex = (self.currentFrameIndex + 1) % self.spinnerFrames.count
        }
      }
    }
    spinnerThread?.start()
  }
  
  func stop(success: Bool = true, message: String? = nil) {
    guard isRunning else { return }
    isRunning = false
    
    // Clear the spinner line
    print("\r", terminator: "")
    // Clear to end of line
    print("\u{1B}[K", terminator: "")
    
    if let finalMessage = message {
      print(finalMessage)
    } else if !success {
      // Only show error messages, not success
      print("❌ \(self.message)")
    }
    // Success: just clear the spinner, don't print anything
    
    fflush(stdout)
  }
  
  deinit {
    stop()
  }
}

// Convenience function for wrapping async operations
func withSpinner<T>(
  message: String,
  operation: () throws -> T
) rethrows -> T {
  let spinner = LoadingSpinner(message: message)
  spinner.start()
  defer {
    spinner.stop()
  }
  return try operation()
}

// Convenience function for async operations
func withSpinner<T>(
  message: String,
  operation: () async throws -> T
) async rethrows -> T {
  let spinner = LoadingSpinner(message: message)
  spinner.start()
  defer {
    spinner.stop()
  }
  return try await operation()
}
