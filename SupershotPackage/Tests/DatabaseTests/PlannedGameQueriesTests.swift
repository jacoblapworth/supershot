import CustomDump
import Dependencies
import Foundation
import SQLiteData
import TestSupport
import Testing

@testable import Database
@testable import GameCore

extension SupershotTestSuite {
  @MainActor
  struct PlannedGameQueriesTests {
    private func setup() throws -> GameSetupDraft {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      try database.write { db in
        try Team.insert {
          Team(id: UUID(1), name: "A")
          Team(id: UUID(2), name: "B")
        }.execute(db)
      }
      return GameSetupDraft(
        game: Game(
          id: UUID(3), startedAt: nil, teamAID: UUID(1), teamBID: UUID(2),
          createdAt: Date(timeIntervalSince1970: 1_000),
          scheduledAt: Date(timeIntervalSince1970: 2_000), court: "3"),
        periods: testGamePeriods(gameID: UUID(3))
      )
    }

    @Test func plansAreListedWithMetadataButDoNotCountAsPlayed() throws {
      @Dependency(\.defaultDatabase) var database
      let draft = try setup()
      try database.write { db in _ = try draft.save(db) }
      try database.read { db in
        let row = try #require(GamesRequest().fetch(db).games.first)
        #expect(row.isPlanned)
        #expect(!row.isInProgress)
        #expect(!row.isCompleted)
        expectNoDifference(row.court, "3")
        expectNoDifference(row.scheduledAt, draft.game.scheduledAt)
        expectNoDifference(try TeamsRequest().fetch(db).teams.map(\.gameCount), [0, 0])
        #expect(try GameDetailRequest(gameID: draft.game.id).fetch(db).detail == nil)
        let stats = TeamStatistics(teamID: UUID(1), games: [draft.game], goals: [])
        expectNoDifference(stats.gamesPlayed, 0)
      }
    }

    @Test func repeatedSavesReplacePeriodsAndRetainIdentityAndCreationDate() throws {
      @Dependency(\.defaultDatabase) var database
      var draft = try setup()
      try database.write { db in _ = try draft.save(db) }
      draft.periods[0].durationSeconds = 60
      draft.game.court = "A"
      for _ in 0..<3 {
        try database.write { db in _ = try draft.save(db, requiresExistingGame: true) }
      }
      try database.read { db in
        let snapshot = try GameSnapshot.fetch(db, gameID: draft.game.id)
        expectNoDifference(snapshot.game, draft.game)
        expectNoDifference(snapshot.periods, draft.periods)
        expectNoDifference(try Game.fetchCount(db), 1)
        expectNoDifference(try GamePeriod.fetchCount(db), 4)
      }
    }

    @Test func completedDetailsRetainScheduledAndActualDatesAndCourt() throws {
      @Dependency(\.defaultDatabase) var database
      let draft = try setup()
      let startedAt = Date(timeIntervalSince1970: 3_000)
      let finalPhaseIndex = GameTimeline(periods: draft.periods)!.phases.count - 1
      let finalDuration = draft.periods.last!.durationSeconds
      try database.write { db in
        _ = try draft.save(db, startingAt: startedAt)
        try Game.find(draft.game.id).update {
          $0.endedAt = #bind(Date(timeIntervalSince1970: 4_000))
          $0.currentPhaseIndex = #bind(finalPhaseIndex)
          $0.elapsedSeconds = #bind(finalDuration)
        }.execute(db)
      }
      let detail = try database.read {
        try GameDetailRequest(gameID: draft.game.id).fetch($0).detail
      }
      expectNoDifference(detail?.scheduledAt, draft.game.scheduledAt)
      expectNoDifference(detail?.startedAt, startedAt)
      expectNoDifference(detail?.court, "3")
      let snapshot = try database.read { try GameSnapshot.fetch($0, gameID: draft.game.id) }
      #expect(snapshot.isFinalPeriodComplete)
    }

    @Test func staleSaveCannotOverwriteStartedGame() throws {
      @Dependency(\.defaultDatabase) var database
      let draft = try setup()
      let started = try database.write {
        try draft.save($0, startingAt: Date(timeIntervalSince1970: 3_000))
      }
      #expect(throws: GameSetupDraft.SaveError.self) {
        try database.write { db in _ = try draft.save(db) }
      }
      let current = try database.read { try GameSnapshot.fetch($0, gameID: draft.game.id) }
      expectNoDifference(current, started)
    }

    @Test func deletedPlanCannotBeRecreatedByAnOpenEditor() throws {
      @Dependency(\.defaultDatabase) var database
      let draft = try setup()
      try database.write { db in
        _ = try draft.save(db)
        try Game.find(draft.game.id).delete().execute(db)
      }
      #expect(throws: GameSetupDraft.SaveError.self) {
        try database.write { db in _ = try draft.save(db, requiresExistingGame: true) }
      }
      expectNoDifference(try database.read { try Game.fetchCount($0) }, 0)
      expectNoDifference(try database.read { try GamePeriod.fetchCount($0) }, 0)
    }
  }
}
