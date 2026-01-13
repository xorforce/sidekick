import Foundation

struct ProjectEntry {
  enum Kind {
    case workspace
    case project
  }

  let url: URL
  let kind: Kind

  var displayName: String { url.lastPathComponent }
  var workspacePath: String? { kind == .workspace ? url.path : nil }
  var projectPath: String? { kind == .project ? url.path : nil }
}

