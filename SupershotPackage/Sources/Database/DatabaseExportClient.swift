import GameCore
import SharedModels

#if DEBUG
  import Dependencies
  import Foundation
  import SQLiteData

  nonisolated package struct DatabaseExportClient: Sendable {
    package var snapshot: @Sendable () async throws -> URL
    package var removeSnapshot: @Sendable (URL) -> Void

    package init(
      snapshot: @escaping @Sendable () async throws -> URL,
      removeSnapshot: @escaping @Sendable (URL) -> Void
    ) {
      self.snapshot = snapshot
      self.removeSnapshot = removeSnapshot
    }
  }

  extension DatabaseExportClient: DependencyKey {
    nonisolated static package var liveValue: Self {
      Self(
        snapshot: {
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
        },
        removeSnapshot: { url in
          try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        })
    }

    nonisolated static package var testValue: Self {
      Self(snapshot: { throw CancellationError() }, removeSnapshot: { _ in })
    }
  }
#endif
