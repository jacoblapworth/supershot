import AppUI
import Database
import Dependencies
import Foundation
import GameCore
import LocationClient
import SharedModels
import UI

package nonisolated enum MockGameData {
  package static let breakDurationSeconds = 60
  package static let periodDurationSeconds = 8 * 60

  package static func periods(
    gameID: Game.ID,
    idOffset: Int,
    count: Int = 4,
    periodDurationSeconds: Int = periodDurationSeconds,
    breakDurationSeconds: Int = breakDurationSeconds
  ) -> [GamePeriod] {
    (0 ..< count).map { position in
      GamePeriod(
        id: UUID(idOffset + position),
        gameID: gameID,
        position: position,
        durationSeconds: periodDurationSeconds,
        breakAfterDurationSeconds: position < count - 1
          ? breakDurationSeconds
          : nil
      )
    }
  }

  package struct GoalEvent: Equatable, Sendable {
    package let centrePassTeamA: Bool
    package let elapsedSeconds: Int
    package let period: Int
    package let teamAScored: Bool

    package init(centrePassTeamA: Bool, elapsedSeconds: Int, period: Int, teamAScored: Bool) {
      self.centrePassTeamA = centrePassTeamA
      self.elapsedSeconds = elapsedSeconds
      self.period = period
      self.teamAScored = teamAScored
    }
  }

  /// Builds a repeatable, match-like scoring sequence with a goal every 20–30 seconds.
  package static func goalEvents(
    throughPeriod finalPeriod: Int,
    elapsedSecondsInFinalPeriod: Int = periodDurationSeconds
  ) -> [GoalEvent] {
    let intervals = [24, 27, 22, 29, 25, 21, 28, 23, 26, 20]
    let teamAScored = [
      true,
      false,
      true,
      false,
      false,
      true,
      true,
      false,
      true,
      false,
      false,
      true,
      false,
      true,
      true,
      false,
      false,
      true,
      false,
      true,
    ]
    var events: [GoalEvent] = []
    var goalIndex = 0

    for period in 1 ... min(max(finalPeriod, 1), 4) {
      let periodLimit =
        period == finalPeriod
          ? min(max(elapsedSecondsInFinalPeriod, 0), periodDurationSeconds)
          : periodDurationSeconds
      var elapsedSeconds = 0
      var intervalIndex = period - 1

      while true {
        elapsedSeconds += intervals[intervalIndex % intervals.count]
        guard elapsedSeconds <= periodLimit else { break }
        events.append(GoalEvent(
          centrePassTeamA: goalIndex.isMultiple(of: 2),
          elapsedSeconds: elapsedSeconds,
          period: period,
          teamAScored: teamAScored[goalIndex % teamAScored.count]
        ))
        goalIndex += 1
        intervalIndex += 1
      }
    }
    return events
  }
}
