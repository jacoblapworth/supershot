import AlarmClient
import Database
import Dependencies
import Foundation
import GameCore
import IssueReporting
import SharedModels
import SubscriptionClient

public nonisolated struct GameScoreSnapshot: Equatable, Sendable {
  public var canUndo = false
  public var canUndoDuringConfirmation = false
  public var centrePassTeamID: Team.ID
  public var teamAScore = 0
  public var teamBScore = 0

  public init(
    canUndo: Bool = false,
    canUndoDuringConfirmation: Bool = false,
    centrePassTeamID: Team.ID,
    teamAScore: Int = 0,
    teamBScore: Int = 0
  ) {
    self.canUndo = canUndo
    self.canUndoDuringConfirmation = canUndoDuringConfirmation
    self.centrePassTeamID = centrePassTeamID
    self.teamAScore = teamAScore
    self.teamBScore = teamBScore
  }
}

public nonisolated struct LastCentrePassSnapshot: Equatable, Sendable {
  public var centrePassTeamID: Team.ID

  public init(centrePassTeamID: Team.ID) {
    self.centrePassTeamID = centrePassTeamID
  }
}

public nonisolated struct GameScoringClient: Sendable {
  public var recordGoal: @Sendable (RecordGoalCommand) async throws -> GameScoreSnapshot
  public var undo: @Sendable (Game.ID) async throws -> GameScoreSnapshot
  public var selectCentrePass: @Sendable (Game.ID, Team.ID) async throws -> Team.ID
  public var resolveCentrePass:
    @Sendable (Game.ID, Int, Bool) async throws -> LastCentrePassSnapshot

  public static var live: Self {
    Self(
      recordGoal: { command in
        @Dependency(\.gameSession) var session
        return try await GameScoreSnapshot(snapshot: session.execute(command.gameID, .recordGoal(command), command.createdAt).acceptedSnapshot())
      },
      undo: { gameID in
        @Dependency(\.gameSession) var session
        @Dependency(\.date.now) var now
        return try await GameScoreSnapshot(snapshot: session.execute(gameID, .undoGoal, now).acceptedSnapshot())
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
          .resolveCentrePass(completedPeriod: period, taken: taken),
          now
        ).acceptedSnapshot()
        return LastCentrePassSnapshot(centrePassTeamID:
          snapshot.game.scoring.centrePass(teamAID: snapshot.teamA.id, teamBID: snapshot.teamB.id))
      }
    )
  }

  public static var unimplemented: Self {
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

  public init(
    recordGoal: @escaping @Sendable (RecordGoalCommand) async throws -> GameScoreSnapshot,
    undo: @escaping @Sendable (Game.ID) async throws -> GameScoreSnapshot,
    selectCentrePass: @escaping @Sendable (Game.ID, Team.ID) async throws -> Team.ID,
    resolveCentrePass:
    @escaping @Sendable (Game.ID, Int, Bool) async throws -> LastCentrePassSnapshot
  ) {
    self.recordGoal = recordGoal
    self.undo = undo
    self.selectCentrePass = selectCentrePass
    self.resolveCentrePass = resolveCentrePass
  }
}

public extension DependencyValues {
  nonisolated var gameScoring: GameScoringClient {
    get { self[GameScoringClientKey.self] }
    set { self[GameScoringClientKey.self] = newValue }
  }
}

private nonisolated enum GameScoringClientKey: DependencyKey {
  static var liveValue: GameScoringClient {
    .live
  }

  static var testValue: GameScoringClient {
    .unimplemented
  }
}

public nonisolated extension GameScoreSnapshot {
  init(snapshot: GameSnapshot) {
    self.init(
      canUndo: !snapshot.goals.isEmpty,
      canUndoDuringConfirmation: snapshot.canUndoDuringConfirmation,
      centrePassTeamID: snapshot.game.scoring.centrePass(teamAID: snapshot.teamA.id, teamBID: snapshot.teamB.id),
      teamAScore: snapshot.teamAScore,
      teamBScore: snapshot.teamBScore
    )
  }
}
