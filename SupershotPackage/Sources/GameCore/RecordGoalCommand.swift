import Foundation
import SharedModels

public nonisolated struct RecordGoalCommand: Equatable, Sendable {
  public enum Source: Equatable, Sendable {
    case app
    case liveActivity
  }

  public var source: Source
  public var gameID: Game.ID
  public var teamID: Team.ID
  public var expectedPhaseIndex: Int
  public var goalID: Goal.ID
  public var createdAt: Date
  public var points = 1
  public var scoringContext: GameScoringContext?

  public init(
    gameID: Game.ID, teamID: Team.ID, expectedPhaseIndex: Int, goalID: Goal.ID, createdAt: Date,
    points: Int = 1, scoringContext: GameScoringContext? = nil, source: Source = .app
  ) {
    self.source = source
    self.gameID = gameID
    self.teamID = teamID
    self.expectedPhaseIndex = expectedPhaseIndex
    self.goalID = goalID
    self.createdAt = createdAt
    self.points = points
    self.scoringContext = scoringContext
  }
}
