import Database
import GameCore
import SharedModels
import SwiftUI
import WidgetSupport

package nonisolated extension GameListItem {
  var teamABibColor: Color {
    Color(hex: teamABibColorHex)
  }

  var teamBBibColor: Color {
    Color(hex: teamBBibColorHex)
  }

  init(
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

package nonisolated extension TeamListItem {
  var color: Color {
    Color(hex: colorHex)
  }

  init(color: Color, gameCount: Int, id: Team.ID, name: String) {
    self.init(
      colorHex: color.hex(),
      gameCount: gameCount,
      id: id,
      name: name
    )
  }
}

package nonisolated extension GoalTimelineItem {
  var scoringTeamBibColor: Color {
    Color(hex: scoringTeamBibColorHex)
  }

  init(
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

package nonisolated extension GameAnalysis {
  var teamABibColor: Color {
    Color(hex: teamABibColorHex)
  }

  var teamBBibColor: Color {
    Color(hex: teamBBibColorHex)
  }

  init(
    goalTimeline: GoalTimeline = GoalTimeline(), periods: [GamePeriod] = [],
    statistics: CompletedGameStatistics = CompletedGameStatistics(),
    statisticsByPeriod: [Int: CompletedGameStatistics] = [:],
    teamABibColor: Color, teamAName: String = "",
    teamBBibColor: Color = ColorPalette.red, teamBName: String = ""
  ) {
    self.init(
      goalTimeline: goalTimeline,
      periods: periods,
      statistics: statistics,
      statisticsByPeriod: statisticsByPeriod,
      teamABibColorHex: teamABibColor.hex(),
      teamAName: teamAName,
      teamBBibColorHex: teamBBibColor.hex(),
      teamBName: teamBName
    )
  }
}

package nonisolated extension CompletedGameDetail {
  var teamABibColor: Color {
    Color(hex: teamABibColorHex)
  }

  var teamBBibColor: Color {
    Color(hex: teamBBibColorHex)
  }

  init(
    endedAt: Date, goalTimeline: GoalTimeline, id: Game.ID, location: GameLocation? = nil,
    periods: [GamePeriod] = [], startedAt: Date,
    statistics: CompletedGameStatistics = CompletedGameStatistics(),
    statisticsByPeriod: [Int: CompletedGameStatistics] = [:],
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
      statisticsByPeriod: statisticsByPeriod,
      teamABibColorHex: teamABibColor.hex(),
      teamAName: teamAName,
      teamAScore: teamAScore,
      teamBBibColorHex: teamBBibColor.hex(),
      teamBName: teamBName,
      teamBScore: teamBScore
    )
  }
}
