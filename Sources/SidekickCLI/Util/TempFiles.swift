import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Best-effort temporary file cleanup.
/// - Cleans up on normal exit (`atexit`)
/// - Cleans up on SIGINT/SIGTERM (Ctrl-C / terminate) using DispatchSource signals
final class TempFileManager {
  static let shared = TempFileManager()

  private let lock = NSLock()
  private var trackedPaths = Set<String>()
  private var installed = false
  private var sigintSource: DispatchSourceSignal?
  private var sigtermSource: DispatchSourceSignal?

  private init() {}

  func makeTempFileURL(prefix: String, fileExtension: String) -> URL {
    installCleanupHooksIfNeeded()
    let filename = "\(prefix)-\(UUID().uuidString).\(fileExtension)"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    track(url)
    return url
  }

  func remove(_ url: URL) {
    untrack(url)
    try? FileManager.default.removeItem(at: url)
  }

  // MARK: - Internals

  private func track(_ url: URL) {
    lock.lock()
    trackedPaths.insert(url.path)
    lock.unlock()
  }

  private func untrack(_ url: URL) {
    lock.lock()
    trackedPaths.remove(url.path)
    lock.unlock()
  }

  private func cleanupAll() {
    lock.lock()
    let paths = trackedPaths
    trackedPaths.removeAll()
    lock.unlock()

    for path in paths {
      try? FileManager.default.removeItem(atPath: path)
    }
  }

  private func installCleanupHooksIfNeeded() {
    lock.lock()
    defer { lock.unlock() }
    guard !installed else { return }
    installed = true

    atexit {
      TempFileManager.shared.cleanupAll()
    }

    #if canImport(Darwin)
    // Convert default signal handling into DispatchSources so we can run cleanup.
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    let queue = DispatchQueue(label: "sidekick.tempfiles.signals")

    let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
    intSource.setEventHandler {
      TempFileManager.shared.cleanupAll()
      exit(130)
    }
    intSource.resume()
    sigintSource = intSource

    let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
    termSource.setEventHandler {
      TempFileManager.shared.cleanupAll()
      exit(143)
    }
    termSource.resume()
    sigtermSource = termSource
    #endif
  }
}

