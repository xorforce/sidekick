import Foundation

func detectProjects(in root: URL) -> [ProjectEntry] {
  guard let enumerator = FileManager.default.enumerator(
    at: root,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
  ) else {
    return []
  }

  var results: [ProjectEntry] = []
  for case let url as URL in enumerator {
    let depth = url.pathComponents.count - root.pathComponents.count
    if depth > 3 {
      enumerator.skipDescendants()
      continue
    }

    switch url.pathExtension {
    case "xcworkspace":
      results.append(ProjectEntry(url: url, kind: .workspace))
    case "xcodeproj":
      results.append(ProjectEntry(url: url, kind: .project))
    default:
      break
    }
  }

  return results.sorted { lhs, rhs in
    if lhs.kind != rhs.kind {
      return lhs.kind == .workspace
    }
    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
  }
}

