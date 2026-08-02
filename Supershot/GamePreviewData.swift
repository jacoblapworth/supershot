#if DEBUG
import Foundation

extension GameListItem {
  static let previewInProgress = Self(
    endedAt: nil,
    id: UUID(),
    startedAt: Date(timeIntervalSince1970: 1_785_659_400),
    teamABibColorHex: "#34C759",
    teamAName: "North London Ravens",
    teamAScore: 18,
    teamBBibColorHex: "#FF9500",
    teamBName: "Westminster Swifts",
    teamBScore: 16
  )

  static let previewCompleted = Self(
    endedAt: Date(timeIntervalSince1970: 1_785_580_200),
    firstBreakDurationSeconds: 240,
    halfTimeDurationSeconds: 600,
    id: UUID(),
    periodDurationSeconds: 900,
    secondBreakDurationSeconds: 240,
    startedAt: Date(timeIntervalSince1970: 1_785_573_000),
    teamAName: "North London Ravens",
    teamAScore: 42,
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
    endedAt: Date(timeIntervalSince1970: 1_785_580_200),
    firstBreakDurationSeconds: 240,
    goals: [
      GoalTimelineItem(
        clockSecondsRemaining: 780,
        id: UUID(),
        period: 1,
        points: 1,
        scoringTeamName: "North London Ravens",
        teamAScore: 1,
        teamBScore: 0
      ),
      GoalTimelineItem(
        clockSecondsRemaining: 420,
        id: UUID(),
        period: 2,
        points: 2,
        scoringTeamBibColorHex: TeamColorPalette.red,
        scoringTeamName: "Westminster Swifts",
        teamAScore: 1,
        teamBScore: 2
      ),
    ],
    halfTimeDurationSeconds: 600,
    id: UUID(),
    periodDurationSeconds: 900,
    secondBreakDurationSeconds: 240,
    startedAt: Date(timeIntervalSince1970: 1_785_573_000),
    statistics: CompletedGameStatistics(
      teamA: TeamGameStatistics(
        averageTimeToGoalSeconds: 18,
        centrePass: CentrePassStatistics(
          conversions: 31,
          inferredTurnovers: 7,
          opportunities: 38
        )
      ),
      teamB: TeamGameStatistics(
        averageTimeToGoalSeconds: 22,
        centrePass: CentrePassStatistics(
          conversions: 29,
          inferredTurnovers: 8,
          opportunities: 37
        )
      )
    ),
    teamAName: "North London Ravens",
    teamAScore: 42,
    teamBName: "Westminster Swifts",
    teamBScore: 38
  )

  static let previewDraw = Self(
    endedAt: Date(timeIntervalSince1970: 1_785_580_200),
    goals: [],
    id: UUID(),
    startedAt: Date(timeIntervalSince1970: 1_785_573_000),
    teamAName: "Ravens",
    teamAScore: 24,
    teamBName: "Swifts",
    teamBScore: 24
  )

  static let previewNoGoals = Self(
    endedAt: Date(timeIntervalSince1970: 1_785_580_200),
    goals: [],
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
#endif
