import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
    $0.date.now = Date(timeIntervalSince1970: 1_000)
    $0.gameTimer.refreshActivity = { _ in }
  })
  struct LiveActivityScoringTests {
    @Test
    func goalIntentRecordsBothTeamsAndAlternatesCentrePass() async throws {
      @Dependency(\.defaultDatabase) var database
      try seedGame()
      _ = try await ScoreGoalIntent(
        gameID: UUID(3), teamID: UUID(2), expectedPhaseIndex: 0
      ).perform()
      let first = try await database.read { try GameSnapshot.fetch($0, gameID: UUID(3)) }
      #expect(first.teamBScore == 1)
      #expect(first.game.centrePassTeamID == UUID(2))
      #expect(first.goals.first?.elapsedSeconds == 100)
      #expect(first.goals.first?.centrePassTeamID == UUID(1))
      #expect(first.goals.first?.gamePeriodID == testGamePeriodID(gameID: UUID(3), position: 0))

      _ = try await ScoreGoalIntent(
        gameID: UUID(3), teamID: UUID(1), expectedPhaseIndex: 0
      ).perform()
      let second = try await database.read { try GameSnapshot.fetch($0, gameID: UUID(3)) }
      #expect(second.teamAScore == 1)
      #expect(second.teamBScore == 1)
      #expect(second.game.centrePassTeamID == UUID(1))
    }

    @Test(arguments: ["paused", "expired", "break", "finished", "confirmation", "phase", "team"])
    func rejectsUnavailableGoals(reason: String) async throws {
      @Dependency(\.defaultDatabase) var database
      try seedGame(reason: reason)
      await #expect(throws: (any Error).self) {
        try await database.write { db in
          try ScoringFeature.insertGoal(
            db, gameID: UUID(3), teamID: reason == "team" ? UUID(99) : UUID(1),
            expectedPhaseIndex: reason == "phase" ? 2 : reason == "break" ? 1 : 0,
            goalID: UUID(4), createdAt: Date(timeIntervalSince1970: 1_000)
          )
        }
      }
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: UUID(3)) }
      #expect(snapshot.goals.isEmpty)
      #expect(snapshot.game.centrePassTeamID == UUID(1))
    }

    private func seedGame(reason: String = "running") throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      try database.write { db in
        try Team.insert {
          Team(id: UUID(1), name: "Ravens")
          Team(id: UUID(2), name: "Swifts")
        }.execute(db)
        try Game.insert {
          Game(
            id: UUID(3), startedAt: Date(timeIntervalSince1970: 900),
            endedAt: reason == "finished" ? Date(timeIntervalSince1970: 999) : nil,
            teamAID: UUID(1), teamBID: UUID(2), centrePassTeamID: UUID(1),
            isAwaitingCentrePassConfirmation: reason == "confirmation",
            currentPhaseIndex: reason == "break" ? 1 : 0,
            elapsedSeconds: 0,
            timerEndsAt: reason == "paused" ? nil : Date(
              timeIntervalSince1970: reason == "expired" ? 1_000 : 1_800
            )
          )
        }.execute(db)
        try GamePeriod.insert {
          testGamePeriods(gameID: UUID(3), breakDurationSeconds: 120)
        }.execute(db)
      }
    }
  }
}
