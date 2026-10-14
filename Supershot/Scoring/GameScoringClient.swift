import Dependencies
import Foundation
import IssueReporting

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
        @Dependency(\.gameSession) var session
        return GameScoreSnapshot(
          snapshot: try await session.execute(
            command.gameID, .recordGoal(command), command.createdAt
          ).acceptedSnapshot())
      },
      undo: { gameID in
        @Dependency(\.gameSession) var session
        @Dependency(\.date.now) var now
        return GameScoreSnapshot(
          snapshot: try await session.execute(gameID, .undoGoal, now).acceptedSnapshot())
      },
      selectCentrePass: { gameID, teamID in
        @Dependency(\.gameSession) var session
        @Dependency(\.date.now) var now
        _ = try await session.execute(gameID, .selectCentrePass(teamID), now).acceptedSnapshot()
        return teamID
      },
      resolveCentrePass: { gameID, period, taken in
        @Dependency(\.gameSession) var session
        @Dependency(\.date.now) var now
        let snapshot = try await session.execute(
          gameID,
          .resolveCentrePass(completedPeriod: period, taken: taken), now
        ).acceptedSnapshot()
        return LastCentrePassSnapshot(
          centrePassTeamID:
            snapshot.game.scoring.centrePass(teamAID: snapshot.teamA.id, teamBID: snapshot.teamB.id)
        )
      }
    )
  }

  static var unimplemented: Self {
    Self(
      recordGoal: { _ in
        reportIssue("GameScoringClient.recordGoal is unimplemented")
        throw GameScoringError.unavailable
      },
      undo: { _ in
        reportIssue("GameScoringClient.undo is unimplemented")
        throw GameScoringError.unavailable
      },
      selectCentrePass: { _, _ in
        reportIssue("GameScoringClient.selectCentrePass is unimplemented")
        throw GameScoringError.unavailable
      },
      resolveCentrePass: { _, _, _ in
        reportIssue("GameScoringClient.resolveCentrePass is unimplemented")
        throw GameScoringError.unavailable
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

nonisolated extension GameScoreSnapshot {
  init(snapshot: GameSnapshot) {
    self.init(
      canUndo: !snapshot.goals.isEmpty,
      canUndoDuringConfirmation: snapshot.canUndoDuringConfirmation,
      centrePassTeamID: snapshot.game.scoring.centrePass(
        teamAID: snapshot.teamA.id, teamBID: snapshot.teamB.id),
      teamAScore: snapshot.teamAScore, teamBScore: snapshot.teamBScore)
  }
}
