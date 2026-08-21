import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct TeamsListFeatureTests {
    @Test
    func teamsListIsAlphabeticalWithGameCounts() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
          Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
          Team(id: UUID(-3), name: "Aces", colorHex: "#34C759")
          Game(
            id: UUID(-1),
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: nil,
            teamAID: UUID(-1),
            teamBID: UUID(-2)
          )
          Game(
            id: UUID(-2),
            startedAt: Date(timeIntervalSince1970: 2_000),
            endedAt: Date(timeIntervalSince1970: 3_000),
            teamAID: UUID(-3),
            teamBID: UUID(-1)
          )
        }
      }

      let value = try await database.read { db in
        try TeamsRequest().fetch(db)
      }

      expectNoDifference(
        value.teams,
        [
          TeamListItem(
            colorHex: "#34C759",
            gameCount: 1,
            id: UUID(-3),
            name: "Aces"
          ),
          TeamListItem(
            colorHex: TeamColorPalette.blue,
            gameCount: 2,
            id: UUID(-1),
            name: "Ravens"
          ),
          TeamListItem(
            colorHex: TeamColorPalette.red,
            gameCount: 1,
            id: UUID(-2),
            name: "Swifts"
          ),
        ]
      )
    }
  }
}
