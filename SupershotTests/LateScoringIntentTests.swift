#if os(iOS)
import SharedModels
import GameCore
import Database
import GameServices
import Dependencies
import DependenciesTestSupport
import CustomDump
import Foundation
import SQLiteData
import Testing
@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.date.now = Date(timeIntervalSince1970: 1_000)
    $0.uuid = .incrementing
    $0.gameTimer.refreshActivity = { _ in }
  })
  struct LateScoringIntentTests {
    enum Window: CaseIterable {
      case runningBreak, pausedBreak, manualBreak, waitingQuarter, finalQuarter
    }

    @Test(arguments: Window.allCases, [false, true])
    func rejectsLegacyLateGoalsWithoutChangingScoreClockOrConfirmation(window: Window, pending: Bool) async throws {
      @Dependency(\.defaultDatabase) var database
      let game = try seed(window: window, pending: pending)
      let completed = game.lateScoringPeriodNumber!
      for team in [UUID(1), UUID(2)] {
        await #expect(throws: (any Error).self) {
          try await ScoreGoalIntent(gameID: game.id, teamID: team,
            expectedPhaseIndex: game.currentPhaseIndex, completedPeriodNumber: completed).perform()
        }
      }
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: game.id) }
      expectNoDifference(snapshot.teamAScore, 0)
      expectNoDifference(snapshot.teamBScore, 0)
      expectNoDifference(snapshot.game.countdown, game.countdown)
      expectNoDifference(snapshot.game.currentPhaseIndex, game.currentPhaseIndex)
      expectNoDifference(snapshot.game.isAwaitingCentrePassConfirmation, pending)
      expectNoDifference(snapshot.game.centrePassTeamID, game.centrePassTeamID)
      #expect(snapshot.goals.isEmpty)
      let content = GameActivityAttributes.ContentState(
        centrePassTeamID: snapshot.game.centrePassTeamID!,
        elapsedSeconds: snapshot.game.elapsedSeconds, phaseIndex: snapshot.game.currentPhaseIndex,
        phase: snapshot.currentPhase, teamAScore: snapshot.teamAScore, teamBScore: snapshot.teamBScore,
        timerEndsAt: snapshot.game.timerEndsAt, isAwaitingCentrePassConfirmation: pending,
        lateScoringPeriodNumber: completed)
      expectNoDifference(content.scoringContext, .completedPeriod(number: completed))
      #expect(!content.canScoreGoal)
    }

    private func seed(window: Window, pending: Bool) throws -> Game {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let game = Game(
        id: UUID(3), startedAt: Date(timeIntervalSince1970: 900),
        teamAID: UUID(1), teamBID: UUID(2), centrePassTeamID: UUID(1),
        isAwaitingCentrePassConfirmation: pending,
        lateScoringPeriodNumber: window == .finalQuarter ? 4 : 1,
        currentPhaseIndex: window == .finalQuarter ? 6 : window == .waitingQuarter ? 2 : 1,
        elapsedSeconds: window == .finalQuarter ? 900 : (window == .waitingQuarter || window == .manualBreak) ? 0 : 20,
        timerEndsAt: window == .runningBreak ? Date(timeIntervalSince1970: 1_100) : nil
      )
      try database.write { db in
        try Team.insert {
          Team(id: UUID(1), name: "Ravens")
          Team(id: UUID(2), name: "Swifts")
        }.execute(db)
        try Game.insert { game }.execute(db)
        try GamePeriod.insert { testGamePeriods(gameID: game.id, breakDurationSeconds: 120) }.execute(db)
      }
      return game
    }
  }
}

#endif
