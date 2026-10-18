import Database
import GameCore
import SharedModels
import SwiftUI
import WidgetSupport

nonisolated extension GameListItem {
  package var teamABibColor: Color { Color(hex: teamABibColorHex) }
  package var teamBBibColor: Color { Color(hex: teamBBibColorHex) }
  package init(
    currentQuarter: Int = 1, endedAt: Date? = nil, id: Game.ID, periods: [GamePeriod] = [],
    startedAt: Date, teamABibColor: Color, teamAName: String, teamAScore: Int,
    teamBBibColor: Color = ColorPalette.red, teamBName: String, teamBScore: Int
  ) {
    self.init(
      currentQuarter: currentQuarter,
      endedAt: endedAt,
      id: id,
      periods: periods,
      startedAt: startedAt,
      teamABibColorHex: teamABibColor.hex(),
      teamAName: teamAName,
      teamAScore: teamAScore,
      teamBBibColorHex: teamBBibColor.hex(),
      teamBName: teamBName,
      teamBScore: teamBScore
    )
  }
}

nonisolated extension TeamListItem {
  package var color: Color { Color(hex: colorHex) }
  package init(color: Color, gameCount: Int, id: Team.ID, name: String) {
    self.init(
      colorHex: color.hex(),
      gameCount: gameCount,
      id: id,
      name: name
    )
  }
}

nonisolated extension GoalTimelineItem {
  package var scoringTeamBibColor: Color { Color(hex: scoringTeamBibColorHex) }
  package init(
    clockSecondsRemaining: Int, id: Goal.ID, period: Int, points: Int,
    scoringTeamBibColor: Color, scoringTeamName: String,
    scoringTeamSide: GoalTimelineTeamSide, teamAScore: Int, teamBScore: Int
  ) {
    self.init(
      clockSecondsRemaining: clockSecondsRemaining,
      id: id,
      period: period,
      points: points,
      scoringTeamBibColorHex: scoringTeamBibColor.hex(),
      scoringTeamName: scoringTeamName,
      scoringTeamSide: scoringTeamSide,
      teamAScore: teamAScore,
      teamBScore: teamBScore
    )
  }
}

nonisolated extension GameAnalysis {
  package var teamABibColor: Color { Color(hex: teamABibColorHex) }
  package var teamBBibColor: Color { Color(hex: teamBBibColorHex) }
  package init(
    goalTimeline: GoalTimeline = GoalTimeline(), periods: [GamePeriod] = [],
    statistics: CompletedGameStatistics = CompletedGameStatistics(),
    teamABibColor: Color, teamAName: String = "",
    teamBBibColor: Color = ColorPalette.red, teamBName: String = ""
  ) {
    self.init(
      goalTimeline: goalTimeline,
      periods: periods,
      statistics: statistics,
      teamABibColorHex: teamABibColor.hex(),
      teamAName: teamAName,
      teamBBibColorHex: teamBBibColor.hex(),
      teamBName: teamBName
    )
  }
}

nonisolated extension CompletedGameDetail {
  package var teamABibColor: Color { Color(hex: teamABibColorHex) }
  package var teamBBibColor: Color { Color(hex: teamBBibColorHex) }
  package init(
    endedAt: Date, goalTimeline: GoalTimeline, id: Game.ID, location: GameLocation? = nil,
    periods: [GamePeriod] = [], startedAt: Date,
    statistics: CompletedGameStatistics = CompletedGameStatistics(),
    teamABibColor: Color, teamAName: String, teamAScore: Int,
    teamBBibColor: Color = ColorPalette.red, teamBName: String, teamBScore: Int
  ) {
    self.init(
      endedAt: endedAt,
      goalTimeline: goalTimeline,
      id: id,
      location: location,
      periods: periods,
      startedAt: startedAt,
      statistics: statistics,
      teamABibColorHex: teamABibColor.hex(),
      teamAName: teamAName,
      teamAScore: teamAScore,
      teamBBibColorHex: teamBBibColor.hex(),
      teamBName: teamBName,
      teamBScore: teamBScore
    )
  }
}

