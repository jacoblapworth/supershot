#if DEBUG
import Dependencies
import Foundation
import SQLiteData

nonisolated struct DatabaseExportClient: Sendable {
  var snapshot: @Sendable () async throws -> URL
  var removeSnapshot: @Sendable (URL) -> Void
}

extension DatabaseExportClient: DependencyKey {
  nonisolated static var liveValue: Self {
    Self(snapshot: {
      @Dependency(\.defaultDatabase) var database
      @Dependency(\.uuid) var uuid
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(uuid().uuidString, isDirectory: true)
      return try await Task.detached {
        try FileManager.default.createDirectory(
          at: directory, withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("Supershot.sqlite")
        do {
          let destination = try DatabaseQueue(path: url.path)
          defer { try? destination.close() }
          try database.backup(to: destination)
          try destination.close()
          return url
        } catch {
          try? FileManager.default.removeItem(at: directory)
          throw error
        }
      }.value
    }, removeSnapshot: { url in
      try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    })
  }

  nonisolated static var testValue: Self {
    Self(snapshot: { throw CancellationError() }, removeSnapshot: { _ in })
  }
}
#endif
