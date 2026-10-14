import Dependencies
import Foundation
import IssueReporting
import SQLiteData

nonisolated struct GameScoreSnapshot: Equatable, Sendable {
  var canUndo = false
  var canUndoDuringConfirmation = false
  var centrePassTeamID: Team.ID
  var teamAScore = 0
  var teamBScore = 0
}

nonisolated struct LastCentrePassSnapshot: Equatable, Sendable {
  var centrePassTeamID: Team.ID
}

nonisolated struct RecordGoalCommand: Equatable, Sendable {
  var gameID: Game.ID
  var teamID: Team.ID
  var expectedPhaseIndex: Int
  var goalID: Goal.ID
  var createdAt: Date
  var points = 1
  var scoringContext: GameScoringContext?
}

nonisolated struct GameScoringClient: Sendable {
  var recordGoal: @Sendable (RecordGoalCommand) async throws -> GameScoreSnapshot
  var undo: @Sendable (Game.ID) async throws -> GameScoreSnapshot
  var selectCentrePass: @Sendable (Game.ID, Team.ID) async throws -> Team.ID
  var resolveCentrePass: @Sendable (Game.ID, Int, Bool) async throws -> LastCentrePassSnapshot

  static var live: Self {
    Self(
      recordGoal: { command in
        @Dependency(\.defaultDatabase) var database
        return try await database.write { db in
          try ScoringPersistence.insertGoal(
            db, gameID: command.gameID, teamID: command.teamID,
            expectedPhaseIndex: command.expectedPhaseIndex, goalID: command.goalID,
            createdAt: command.createdAt, points: command.points,
            scoringContext: command.scoringContext)
        }
      },
      undo: { gameID in
        @Dependency(\.defaultDatabase) var database
        return try await database.write { try ScoringPersistence.undo($0, gameID: gameID) }
      },
      selectCentrePass: { gameID, teamID in
        @Dependency(\.defaultDatabase) var database
        return try await database.write {
          try ScoringPersistence.selectCentrePass($0, gameID: gameID, teamID: teamID)
        }
      },
      resolveCentrePass: { gameID, period, taken in
        @Dependency(\.defaultDatabase) var database
        return try await database.write {
          try ScoringPersistence.resolveCentrePass(
            $0, gameID: gameID, completedPeriod: period, wasLastCentrePassTaken: taken)
        }
      }
    )
  }

  static var unimplemented: Self {
    Self(
      recordGoal: { _ in
        reportIssue("GameScoringClient.recordGoal is unimplemented")
        throw ScoringPersistenceError.goalUnavailable
      },
      undo: { _ in
        reportIssue("GameScoringClient.undo is unimplemented")
        throw ScoringPersistenceError.goalUnavailable
      },
      selectCentrePass: { _, _ in
        reportIssue("GameScoringClient.selectCentrePass is unimplemented")
        throw ScoringPersistenceError.goalUnavailable
      },
      resolveCentrePass: { _, _, _ in
        reportIssue("GameScoringClient.resolveCentrePass is unimplemented")
        throw ScoringPersistenceError.goalUnavailable
      }
    )
  }
}

extension DependencyValues {
  nonisolated var gameScoring: GameScoringClient {
    get { self[GameScoringClientKey.self] }
    set { self[GameScoringClientKey.self] = newValue }
  }
}

private nonisolated enum GameScoringClientKey: DependencyKey {
  static var liveValue: GameScoringClient { .live }
  static var testValue: GameScoringClient { .unimplemented }
}
