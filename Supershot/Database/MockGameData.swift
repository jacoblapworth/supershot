#if DEBUG
import Dependencies
import Foundation

nonisolated enum MockGameData {
  static let breakDurationSeconds = 60
  static let periodDurationSeconds = 8 * 60

  static func periods(
    gameID: Game.ID,
    idOffset: Int,
    count: Int = 4,
    periodDurationSeconds: Int = periodDurationSeconds,
    breakDurationSeconds: Int = breakDurationSeconds
  ) -> [GamePeriod] {
    (0..<count).map { position in
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

  struct GoalEvent: Equatable, Sendable {
    let centrePassTeamA: Bool
    let elapsedSeconds: Int
    let period: Int
    let teamAScored: Bool
  }

  /// Builds a repeatable, match-like scoring sequence with a goal every 20–30 seconds.
  static func goalEvents(
    throughPeriod finalPeriod: Int,
    elapsedSecondsInFinalPeriod: Int = periodDurationSeconds
  ) -> [GoalEvent] {
    let intervals = [24, 27, 22, 29, 25, 21, 28, 23, 26, 20]
    let teamAScored = [
      true, false, true, false, false,
      true, true, false, true, false,
      false, true, false, true, true,
      false, false, true, false, true,
    ]
    var events: [GoalEvent] = []
    var goalIndex = 0

    for period in 1...min(max(finalPeriod, 1), 4) {
      let periodLimit = period == finalPeriod
        ? min(max(elapsedSecondsInFinalPeriod, 0), periodDurationSeconds)
        : periodDurationSeconds
      var elapsedSeconds = 0
      var intervalIndex = period - 1

      while true {
        elapsedSeconds += intervals[intervalIndex % intervals.count]
        guard elapsedSeconds <= periodLimit else { break }
        events.append(
          GoalEvent(
            centrePassTeamA: goalIndex.isMultiple(of: 2),
            elapsedSeconds: elapsedSeconds,
            period: period,
            teamAScored: teamAScored[goalIndex % teamAScored.count]
          )
        )
        goalIndex += 1
        intervalIndex += 1
      }
    }
    return events
  }
}
#endif
