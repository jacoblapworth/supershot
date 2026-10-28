import CustomDump
@testable import Database
import Dependencies
import Foundation
@testable import GameCore
import SQLiteData
import Testing
import TestSupport

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
          createdAt: Date(timeIntervalSince1970: 1000),
          scheduledAt: Date(timeIntervalSince1970: 2000), court: "3"
        ),
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
        try expectNoDifference(TeamsRequest().fetch(db).teams.map(\.gameCount), [0, 0])
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
      for _ in 0 ..< 3 {
        try database.write { db in _ = try draft.save(db, requiresExistingGame: true) }
      }
      try database.read { db in
        let snapshot = try GameSnapshot.fetch(db, gameID: draft.game.id)
        expectNoDifference(snapshot.game, draft.game)
        expectNoDifference(snapshot.periods, draft.periods)
        try expectNoDifference(Game.fetchCount(db), 1)
        try expectNoDifference(GamePeriod.fetchCount(db), 4)
      }
    }

    @Test func completedDetailsRetainScheduledAndActualDatesAndCourt() throws {
      @Dependency(\.defaultDatabase) var database
      let draft = try setup()
      let startedAt = Date(timeIntervalSince1970: 3000)
      let finalPhaseIndex = try #require(GameTimeline(periods: draft.periods)?.phases.count) - 1
      let finalDuration = try #require(draft.periods.last?.durationSeconds)
      try database.write { db in
        _ = try draft.save(db)
        try Game.find(draft.game.id).update {
          $0.startedAt = #bind(startedAt)
          $0.endedAt = #bind(Date(timeIntervalSince1970: 4000))
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

    @Test func editingSetupResetsAnUnstartedClockToMatchTheNewPeriods() throws {
      @Dependency(\.defaultDatabase) var database
      var draft = try setup()
      try database.write { db in
        _ = try draft.save(db)
        try Game.find(draft.game.id).update { $0.elapsedSeconds = 300 }.execute(db)
      }
      draft.periods[0].durationSeconds = 60
      let snapshot = try database.write { try draft.save($0, requiresExistingGame: true) }
      #expect(snapshot.game.startedAt == nil)
      expectNoDifference(snapshot.game.elapsedSeconds, 0)
      expectNoDifference(snapshot.game.timing.status(in: snapshot.timeline), .ready)
    }

    @Test func staleSaveCannotOverwriteStartedGame() throws {
      @Dependency(\.defaultDatabase) var database
      let draft = try setup()
      let started = try database.write { db in
        _ = try draft.save(db)
        try Game.find(draft.game.id).update {
          $0.startedAt = #bind(Date(timeIntervalSince1970: 3000))
        }.execute(db)
        return try GameSnapshot.fetch(db, gameID: draft.game.id)
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
      try expectNoDifference(database.read { try Game.fetchCount($0) }, 0)
      try expectNoDifference(database.read { try GamePeriod.fetchCount($0) }, 0)
    }
  }
}
