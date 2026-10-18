import Foundation
import SharedModels

nonisolated public struct RecordGoalCommand: Equatable, Sendable {
  public var gameID: Game.ID
  public var teamID: Team.ID
  public var expectedPhaseIndex: Int
  public var goalID: Goal.ID
  public var createdAt: Date
  public var points = 1
  public var scoringContext: GameScoringContext?

  public init(
    gameID: Game.ID, teamID: Team.ID, expectedPhaseIndex: Int, goalID: Goal.ID, createdAt: Date,
    points: Int = 1, scoringContext: GameScoringContext? = nil
  ) {
    self.gameID = gameID
    self.teamID = teamID
    self.expectedPhaseIndex = expectedPhaseIndex
    self.goalID = goalID
    self.createdAt = createdAt
    self.points = points
    self.scoringContext = scoringContext
  }
}
