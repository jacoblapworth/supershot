import CustomDump
import Database
import Dependencies
import Foundation
import GameCore
import SQLiteData
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor struct PlannedGameImportTests {
    private func command(count: Int = 6) -> PlannedGameImport {
      let teams = [Team(id: UUID(100), name: "A"), Team(id: UUID(101), name: "B")]
      return PlannedGameImport(drafts: (0 ..< count).map { index in
        let id = UUID(200 + index)
        return GameSetupDraft(
          game: Game(
            id: id,
            startedAt: nil,
            teamAID: teams[0].id,
            teamBID: teams[1].id,
            createdAt: Date(timeIntervalSince1970: 1000),
            scheduledAt: Date(timeIntervalSince1970: 2000 + Double(index * 600)),
            court: "2",
            division: "1"
          ),
          periods: testGamePeriods(gameID: id),
          teamsToCreate: teams
        )
      }, matchedTeams: [])
    }

    @Test(arguments: [1, 6]) func atomicImportRetainsMetadataAndReusesTeams(count: Int) throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let command = command(count: count)
      for _ in 0 ..< 2 {
        try database.write { db in
          let result = try command.save(db)
          #expect(result.map(\.game.id) == command.drafts.map(\.game.id))
          #expect(result.allSatisfy { $0.game.isPlanned && $0.game.timerEndsAt == nil && $0.game.court == "2" && $0.game.division == "1" })
        }
      }
      try database.read { db in
        try expectNoDifference(Team.fetchCount(db), 2)
        try expectNoDifference(Game.fetchCount(db), count)
        try expectNoDifference(GamePeriod.fetchCount(db), count * 4)
      }
    }

    @Test func laterFailureRollsBackEarlierGamesAndTeams() throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      var command = command()
      command.drafts[4].periods = []
      try database.write { db in
        // Catch inside the outer transaction to prove the command's own savepoint rolls back.
        #expect(throws: (any Error).self) { try command.save(db) }
        try expectNoDifference(Game.fetchCount(db), 0)
        try expectNoDifference(Team.fetchCount(db), 0)
      }
    }

    @Test func staleMatchAndMissingSchedulePreventWrites() throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      var command = command()
      command.matchedTeams = [Team(id: UUID(999), name: "Deleted")]
      try database.write { db in
        #expect(throws: PlannedGameImport.ImportError.self) { try command.save(db) }
        try expectNoDifference(Game.fetchCount(db), 0)
      }
      command.matchedTeams = []
      command.drafts[0].game.scheduledAt = nil
      try database.write { db in
        #expect(throws: PlannedGameImport.ImportError.self) { try command.save(db) }
        try expectNoDifference(Team.fetchCount(db), 0)
      }
    }
  }
}
