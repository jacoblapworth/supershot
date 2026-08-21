#if DEBUG
import Dependencies
import Foundation

extension GameListItem {
  static let previewInProgress = Self(
    currentQuarter: 3,
    endedAt: nil,
    firstBreakDurationSeconds: MockGameData.breakDurationSeconds,
    halfTimeDurationSeconds: MockGameData.breakDurationSeconds,
    id: UUID(),
    periodDurationSeconds: MockGameData.periodDurationSeconds,
    secondBreakDurationSeconds: MockGameData.breakDurationSeconds,
    startedAt: Date(timeIntervalSince1970: 1_785_659_400),
    teamABibColorHex: "#34C759",
    teamAName: "North London Ravens",
    teamAScore: 16,
    teamBBibColorHex: "#FF9500",
    teamBName: "Westminster Swifts",
    teamBScore: 16
  )

  static let previewCompleted = Self(
    endedAt: Date(timeIntervalSince1970: 1_785_575_100),
    firstBreakDurationSeconds: MockGameData.breakDurationSeconds,
    halfTimeDurationSeconds: MockGameData.breakDurationSeconds,
    id: UUID(),
    periodDurationSeconds: MockGameData.periodDurationSeconds,
    secondBreakDurationSeconds: MockGameData.breakDurationSeconds,
    startedAt: Date(timeIntervalSince1970: 1_785_573_000),
    teamAName: "North London Ravens",
    teamAScore: 38,
    teamBName: "Westminster Swifts",
    teamBScore: 38
  )
}

extension Array where Element == GameListItem {
  static var previewGames: Self {
    [.previewInProgress, .previewCompleted]
  }
}

extension CompletedGameDetail {
  static let previewCompleted = Self(
    endedAt: Date(timeIntervalSince1970: 1_785_575_100),
    firstBreakDurationSeconds: MockGameData.breakDurationSeconds,
    goalTimeline: realisticPreviewTimeline,
    halfTimeDurationSeconds: MockGameData.breakDurationSeconds,
    id: UUID(),
    periodDurationSeconds: MockGameData.periodDurationSeconds,
    secondBreakDurationSeconds: MockGameData.breakDurationSeconds,
    startedAt: Date(timeIntervalSince1970: 1_785_573_000),
    statistics: CompletedGameStatistics(
      teamA: TeamGameStatistics(
        averageTimeToGoalSeconds: 25,
        centrePass: CentrePassStatistics(
          conversions: 20,
          inferredTurnovers: 18,
          opportunities: 38
        )
      ),
      teamB: TeamGameStatistics(
        averageTimeToGoalSeconds: 25,
        centrePass: CentrePassStatistics(
          conversions: 20,
          inferredTurnovers: 18,
          opportunities: 38
        )
      )
    ),
    teamAName: "North London Ravens",
    teamAScore: 38,
    teamBName: "Westminster Swifts",
    teamBScore: 38
  )

  static let previewDraw = Self(
    endedAt: Date(timeIntervalSince1970: 1_785_580_200),
    goalTimeline: .previewEmpty,
    id: UUID(),
    startedAt: Date(timeIntervalSince1970: 1_785_573_000),
    teamAName: "Ravens",
    teamAScore: 24,
    teamBName: "Swifts",
    teamBScore: 24
  )

  static let previewNoGoals = Self(
    endedAt: Date(timeIntervalSince1970: 1_785_580_200),
    goalTimeline: .previewEmpty,
    id: UUID(),
    startedAt: Date(timeIntervalSince1970: 1_785_573_000),
    statistics: CompletedGameStatistics(
      teamA: TeamGameStatistics(
        averageTimeToGoalSeconds: nil,
        centrePass: CentrePassStatistics(
          conversions: 0,
          inferredTurnovers: 0,
          opportunities: 0
        )
      ),
      teamB: TeamGameStatistics(
        averageTimeToGoalSeconds: nil,
        centrePass: CentrePassStatistics(
          conversions: 0,
          inferredTurnovers: 0,
          opportunities: 0
        )
      )
    ),
    teamAName: "Ravens",
    teamAScore: 0,
    teamBName: "Swifts",
    teamBScore: 0
  )
}

private let realisticPreviewTimeline: GoalTimeline = {
  var teamAScore = 0
  var teamBScore = 0
  var goalsByPeriod: [Int: [GoalTimelineItem]] = [:]
  let events = MockGameData.goalEvents(throughPeriod: 4)

  for (index, event) in events.enumerated() {
    if event.teamAScored {
      teamAScore += 1
    } else {
      teamBScore += 1
    }
    goalsByPeriod[event.period, default: []].append(
      GoalTimelineItem(
        clockSecondsRemaining: MockGameData.periodDurationSeconds - event.elapsedSeconds,
        id: UUID(300 + index),
        period: event.period,
        points: 1,
        scoringTeamBibColorHex: event.teamAScored
          ? TeamColorPalette.blue
          : TeamColorPalette.red,
        scoringTeamName: event.teamAScored
          ? "North London Ravens"
          : "Westminster Swifts",
        scoringTeamSide: event.teamAScored ? .teamA : .teamB,
        teamAScore: teamAScore,
        teamBScore: teamBScore
      )
    )
  }

  return GoalTimeline(
    quarters: (1...4).reversed().map { period in
      let goals = goalsByPeriod[period, default: []]
      return GoalTimelineQuarter(
        goals: Array(goals.reversed()),
        period: period,
        teamAQuarterScore: goals.filter { $0.scoringTeamSide == .teamA }.count,
        teamBQuarterScore: goals.filter { $0.scoringTeamSide == .teamB }.count
      )
    }
  )
}()

extension GoalTimeline {
  static let previewEmpty = Self.empty(through: 4)
}
#endif
