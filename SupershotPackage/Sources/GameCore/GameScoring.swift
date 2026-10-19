import Foundation
import SharedModels

/// Scoring rules consume an attributed playing moment, never advance a clock.
nonisolated public struct ScoringOpportunity: Equatable, Sendable {
  public var periodID: GamePeriod.ID
  public var elapsedSeconds: Int
  public var isLate: Bool

  public init(period: GamePeriod, context: GameScoringContext, elapsedSeconds: Int) {
    periodID = period.id
    self.elapsedSeconds = context.isLate ? period.durationSeconds : elapsedSeconds
    isLate = context.isLate
  }
}

nonisolated public struct GameScoringState: Equatable, Sendable {
  public var centrePassTeamID: Team.ID?
  public var isAwaitingCentrePassConfirmation = false
  public var lateScoringPeriodNumber: Int?

  public func centrePass(teamAID: Team.ID, teamBID: Team.ID) -> Team.ID {
    centrePassTeamID == teamBID ? teamBID : teamAID
  }

  mutating public func alternateCentrePass(teamAID: Team.ID, teamBID: Team.ID) {
    centrePassTeamID = centrePass(teamAID: teamAID, teamBID: teamBID) == teamAID ? teamBID : teamAID
  }

  mutating public func resolveCentrePass(taken: Bool, teamAID: Team.ID, teamBID: Team.ID) {
    if isAwaitingCentrePassConfirmation && taken {
      alternateCentrePass(teamAID: teamAID, teamBID: teamBID)
    }
    centrePassTeamID = centrePass(teamAID: teamAID, teamBID: teamBID)
    isAwaitingCentrePassConfirmation = false
  }

  public func canUndoDuringConfirmation(latestGoal: Goal?, periods: [GamePeriod]) -> Bool {
    guard let completed = lateScoringPeriodNumber, let latestGoal, latestGoal.isLate else {
      return false
    }
    return periods.first(where: { $0.id == latestGoal.gamePeriodID })?.number == completed
  }

  mutating public func recordGoal(
    _ command: RecordGoalCommand, opportunity: ScoringOpportunity,
    teamAID: Team.ID, teamBID: Team.ID
  ) throws -> Goal {
    guard command.teamID == teamAID || command.teamID == teamBID else {
      throw GameScoringError.invalidTeam
    }
    let goal = Goal(
      id: command.goalID, gameID: command.gameID, gamePeriodID: opportunity.periodID,
      centrePassTeamID: centrePass(teamAID: teamAID, teamBID: teamBID), teamID: command.teamID,
      elapsedSeconds: opportunity.elapsedSeconds, isLate: opportunity.isLate,
      points: command.points, createdAt: command.createdAt)
    alternateCentrePass(teamAID: teamAID, teamBID: teamBID)
    return goal
  }

  public init(
    centrePassTeamID: Team.ID? = nil, isAwaitingCentrePassConfirmation: Bool = false,
    lateScoringPeriodNumber: Int? = nil
  ) {
    self.centrePassTeamID = centrePassTeamID
    self.isAwaitingCentrePassConfirmation = isAwaitingCentrePassConfirmation
    self.lateScoringPeriodNumber = lateScoringPeriodNumber
  }
}

extension Game {
  nonisolated public var scoring: GameScoringState {
    get {
      GameScoringState(
        centrePassTeamID: centrePassTeamID,
        isAwaitingCentrePassConfirmation: isAwaitingCentrePassConfirmation,
        lateScoringPeriodNumber: lateScoringPeriodNumber)
    }
    set {
      centrePassTeamID = newValue.centrePassTeamID
      isAwaitingCentrePassConfirmation = newValue.isAwaitingCentrePassConfirmation
      lateScoringPeriodNumber = newValue.lateScoringPeriodNumber
    }
  }
}

nonisolated extension GameTimeline {
  public func scoringPeriod(for context: GameScoringContext) -> GamePeriod? {
    periods.first { $0.number == context.periodNumber }
  }
}

nonisolated public enum GameScoringError: Error {
  case invalidTeam
  case unavailable
}
