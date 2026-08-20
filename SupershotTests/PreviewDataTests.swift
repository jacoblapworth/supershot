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
      #expect(counts.goals == 108)
    }

    @Test
    func debugGamesUseRealisticTimingAndScoring() throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      try database.seedDebugExamplesIfNeeded()

      let (games, goals) = try database.read { db in
        (try Game.fetchAll(db), try Goal.fetchAll(db))
      }

      #expect(games.allSatisfy { $0.periodDurationSeconds == 8 * 60 })
      #expect(games.allSatisfy { $0.firstBreakDurationSeconds == 60 })
      #expect(games.allSatisfy { $0.halfTimeDurationSeconds == 60 })
      #expect(games.allSatisfy { $0.secondBreakDurationSeconds == 60 })

      for game in games {
        let gameGoals = goals.filter { $0.gameID == game.id }
        let teamAScore = gameGoals.filter { $0.teamID == game.teamAID }.count
        let teamBScore = gameGoals.filter { $0.teamID == game.teamBID }.count
        #expect(abs(teamAScore - teamBScore) <= 2)

        for periodGoals in Dictionary(grouping: gameGoals, by: \.period).values {
          let elapsedSeconds = periodGoals.map(\.elapsedSeconds).sorted()
          let scoringIntervals = zip([0] + elapsedSeconds, elapsedSeconds).map { $1 - $0 }
          #expect(scoringIntervals.allSatisfy { (20...30).contains($0) })
        }
      }
    }
  }
}
