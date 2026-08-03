import Dependencies
import GRDB
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct PreviewDataTests {
    @Test
    func seedDebugExamplesOnlyOnce() throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      try database.seedDebugExamplesIfNeeded()
      try database.seedDebugExamplesIfNeeded()

      let counts = try database.read { db in
        (
          teams: try Team.fetchCount(db),
          games: try Game.fetchCount(db),
          goals: try Goal.fetchCount(db)
        )
      }

      #expect(counts.teams == 4)
      #expect(counts.games == 2)
      #expect(counts.goals == 4)
    }
  }
}
