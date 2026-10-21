@testable import Database
import Dependencies
@testable import GameCore
import GRDB
@testable import PreviewSupport
@testable import SharedModels
import SQLiteData
@testable import Styleguide
import Testing
import TestSupport
@testable import WidgetSupport

extension SupershotTestSuite {
  @MainActor
  struct PreviewDataTests {
    @Test
    func seedDebugExamplesOnlyOnce() throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      try database.seedDebugExamplesIfNeeded()
      try database.seedDebugExamplesIfNeeded()

      let counts = try database.read { db in
        try (
          teams: Team.fetchCount(db),
          games: Game.fetchCount(db),
          goals: Goal.fetchCount(db)
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

      let (games, goals, periods) = try database.read { db in
        try (Game.fetchAll(db), Goal.fetchAll(db), GamePeriod.fetchAll(db))
      }

      #expect(periods.count == games.count * 4)
      #expect(periods.allSatisfy { $0.durationSeconds == 8 * 60 })
      #expect(
        periods.allSatisfy {
          $0.position == 3 ? $0.breakAfterDurationSeconds == nil : $0.breakAfterDurationSeconds == 60
        }
      )

      for game in games {
        let gameGoals = goals.filter { $0.gameID == game.id }
        let teamAScore = gameGoals.filter { $0.teamID == game.teamAID }.count
        let teamBScore = gameGoals.filter { $0.teamID == game.teamBID }.count
        #expect(abs(teamAScore - teamBScore) <= 2)

        for periodGoals in Dictionary(grouping: gameGoals, by: \.gamePeriodID).values {
          let elapsedSeconds = periodGoals.map(\.elapsedSeconds).sorted()
          let scoringIntervals = zip([0] + elapsedSeconds, elapsedSeconds).map { $1 - $0 }
          #expect(scoringIntervals.allSatisfy { (20 ... 30).contains($0) })
        }
      }
    }
  }
}
