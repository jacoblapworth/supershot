#if os(iOS)
import ActivityKit
import Foundation
import SwiftUI

nonisolated struct GameActivityAttributes: ActivityAttributes {
  nonisolated struct ContentState: Codable, Hashable, Sendable {
    var centrePassTeamID: UUID
    var currentDurationSeconds: Int
    var elapsedSeconds: Int
    var phaseIndex: Int
    var phase: GamePhase
    var teamAScore: Int
    var teamBScore: Int
    var timerEndsAt: Date?
    var isAwaitingCentrePassConfirmation = false
    var lateScoringPeriodNumber: Int?
  }

  var gameID: UUID
  var teamAID: UUID
  var teamAColorHex: String
  var teamAName: String
  var teamBID: UUID
  var teamBColorHex: String
  var teamBName: String
}

nonisolated extension GameActivityAttributes {
  var teamAColor: Color { Color(hex: teamAColorHex) }
  var teamBColor: Color { Color(hex: teamBColorHex) }
}
#endif

#if os(iOS)
nonisolated extension GameActivityAttributes.ContentState {
  var scoringContext: GameScoringContext? {
    GameScoringContext.resolve(phase: phase, countdown: countdown,
      isAwaitingCentrePassConfirmation: isAwaitingCentrePassConfirmation,
      lateScoringPeriodNumber: lateScoringPeriodNumber)
  }
  var isInBreak: Bool { phase.isBreak }
  var period: Int { phase.periodNumber }
  var countdown: GameCountdown { GameCountdown(elapsedSeconds: elapsedSeconds, endsAt: timerEndsAt) }
  var isComplete: Bool { countdown.projection(durationSeconds: phase.durationSeconds).status == .complete }
  var remainingSeconds: Int { countdown.projection(durationSeconds: phase.durationSeconds).remainingSeconds }
}
#endif
