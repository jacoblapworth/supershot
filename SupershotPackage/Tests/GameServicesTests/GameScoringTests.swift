import Dependencies
import CustomDump
import Foundation
import Testing

import TestSupport
@testable import AlarmClient
@testable import Database
@testable import GameCore
@testable import GameServices
@testable import SharedModels
@testable import Styleguide
@testable import SubscriptionClient
@testable import WidgetSupport

// Deliberately outside SupershotTestSuite: these rules need no database bootstrap.
struct GameScoringTests {
  @Test(arguments: [false, true])
  func attributionAndCentrePassAreIndependentOfClock(late: Bool) throws {
    let period = GamePeriod(id: UUID(4), gameID: UUID(3), position: 0, durationSeconds: 900)
    let command = RecordGoalCommand(
      gameID: UUID(3), teamID: UUID(2), expectedPhaseIndex: 0,
      goalID: UUID(5), createdAt: Date(timeIntervalSince1970: 1_000))
    var scoring = GameScoringState(
      centrePassTeamID: UUID(1),
      isAwaitingCentrePassConfirmation: true, lateScoringPeriodNumber: 1)
    let goal = try scoring.recordGoal(
      command,
      opportunity: ScoringOpportunity(
        period: period,
        context: late ? .completedPeriod(number: 1) : .livePeriod(number: 1), elapsedSeconds: 30),
      teamAID: UUID(1), teamBID: UUID(2))
    expectNoDifference(
      goal,
      Goal(
        id: UUID(5), gameID: UUID(3), gamePeriodID: UUID(4),
        centrePassTeamID: UUID(1), teamID: UUID(2), elapsedSeconds: late ? 900 : 30,
        isLate: late, createdAt: Date(timeIntervalSince1970: 1_000)))
    expectNoDifference(
      scoring,
      GameScoringState(
        centrePassTeamID: UUID(2),
        isAwaitingCentrePassConfirmation: true, lateScoringPeriodNumber: 1))
  }

  @Test func confirmationUsesCurrentOwnershipAndIsIdempotent() {
    var scoring = GameScoringState(
      centrePassTeamID: UUID(2), isAwaitingCentrePassConfirmation: true)
    scoring.resolveCentrePass(taken: true, teamAID: UUID(1), teamBID: UUID(2))
    expectNoDifference(scoring, GameScoringState(centrePassTeamID: UUID(1)))
    scoring.resolveCentrePass(taken: true, teamAID: UUID(1), teamBID: UUID(2))
    expectNoDifference(scoring, GameScoringState(centrePassTeamID: UUID(1)))
  }

  @Test func earlierLateGoalIsNotUndoableInNewConfirmationWindow() {
    let periods = testGamePeriods(gameID: UUID(3), count: 2)
    let goal = Goal(
      id: UUID(5), gameID: UUID(3), gamePeriodID: periods[0].id,
      teamID: UUID(1), elapsedSeconds: 900, isLate: true, createdAt: .distantPast)
    let scoring = GameScoringState(
      isAwaitingCentrePassConfirmation: true, lateScoringPeriodNumber: 2)
    expectNoDifference(scoring.canUndoDuringConfirmation(latestGoal: goal, periods: periods), false)
  }
}
