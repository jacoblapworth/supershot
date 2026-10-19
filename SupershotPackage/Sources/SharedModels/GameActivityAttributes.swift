#if os(iOS)
  import ActivityKit
  import Foundation
  import SwiftUI

  nonisolated public struct GameActivityAttributes: ActivityAttributes, Sendable {
    nonisolated public struct ContentState: Codable, Hashable, Sendable {
      public var centrePassTeamID: UUID
      public var elapsedSeconds: Int
      public var phaseIndex: Int
      public var phase: GamePhase
      public var teamAScore: Int
      public var teamBScore: Int
      public var timerEndsAt: Date?
      public var isAwaitingCentrePassConfirmation = false
      public var lateScoringPeriodNumber: Int?

      public init(
        centrePassTeamID: UUID, elapsedSeconds: Int, phaseIndex: Int, phase: GamePhase,
        teamAScore: Int, teamBScore: Int, timerEndsAt: Date? = nil,
        isAwaitingCentrePassConfirmation: Bool = false, lateScoringPeriodNumber: Int? = nil
      ) {
        self.centrePassTeamID = centrePassTeamID
        self.elapsedSeconds = elapsedSeconds
        self.phaseIndex = phaseIndex
        self.phase = phase
        self.teamAScore = teamAScore
        self.teamBScore = teamBScore
        self.timerEndsAt = timerEndsAt
        self.isAwaitingCentrePassConfirmation = isAwaitingCentrePassConfirmation
        self.lateScoringPeriodNumber = lateScoringPeriodNumber
      }
    }

    public var gameID: UUID
    public var teamAID: UUID
    public var teamAColorHex: String
    public var teamAName: String
    public var teamBID: UUID
    public var teamBColorHex: String
    public var teamBName: String

    public init(
      gameID: UUID, teamAID: UUID, teamAColorHex: String, teamAName: String, teamBID: UUID,
      teamBColorHex: String, teamBName: String
    ) {
      self.gameID = gameID
      self.teamAID = teamAID
      self.teamAColorHex = teamAColorHex
      self.teamAName = teamAName
      self.teamBID = teamBID
      self.teamBColorHex = teamBColorHex
      self.teamBName = teamBName
    }
  }

#endif

#if os(iOS)
  nonisolated extension GameActivityAttributes.ContentState {
    public var scoringContext: GameScoringContext? {
      GameScoringContext.resolve(
        phase: phase, countdown: countdown,
        isAwaitingCentrePassConfirmation: isAwaitingCentrePassConfirmation,
        lateScoringPeriodNumber: lateScoringPeriodNumber)
    }
    /// Live Activity scoring is restricted to running playing time; late goals belong in the app.
    public var canScoreGoal: Bool { scoringContext?.isLate == false }
    public var isInBreak: Bool { phase.isBreak }
    public var canControlTimer: Bool {
      !isComplete && (isInBreak || !isAwaitingCentrePassConfirmation)
    }
    public var period: Int { phase.associatedPeriod.number }
    public var countdown: GameCountdown {
      GameCountdown(elapsedSeconds: elapsedSeconds, endsAt: timerEndsAt)
    }
    public var isComplete: Bool {
      countdown.projection(durationSeconds: phase.durationSeconds).status == .complete
    }
    public var remainingSeconds: Int {
      countdown.projection(durationSeconds: phase.durationSeconds).remainingSeconds
    }
  }
#endif
