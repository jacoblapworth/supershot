import AppUI
import Database
import GameCore
import LocationClient
import PaywallFeature
import PreviewSupport
import SharedModels
import SwiftUI
import UI

package struct GameStatisticsView: View {
  package var detail: GameAnalysis
  @State private var breakdown = GameAnalysisBreakdown.wholeGame

  private var breakdownOptions: [GameAnalysisBreakdown] {
    [.wholeGame] + detail.periods.sorted { $0.position < $1.position }.map { .period($0.number) }
  }

  private var statistics: CompletedGameStatistics {
    breakdown.statistics(in: detail)
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Picker("Breakdown", selection: $breakdown) {
        ForEach(breakdownOptions) { option in
          Text(option.title).tag(option)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("gameAnalysis.breakdown")

      VStack(spacing: 16) {
        HStack(alignment: .top, spacing: 16) {
          TeamStatisticsHeader(
            color: detail.teamABibColor,
            name: detail.teamAName
          )

          TeamStatisticsHeader(
            color: detail.teamBBibColor,
            isTrailing: true,
            name: detail.teamBName
          )
        }

        Divider()

        ForEach(GameStatistic.allCases) { metric in
          StatisticComparisonRow(
            teamAName: detail.teamAName,
            teamAColor: detail.teamABibColor,
            teamAStatistics: statistics.teamA,
            teamBName: detail.teamBName,
            teamBColor: detail.teamBBibColor,
            teamBStatistics: statistics.teamB,
            metric: metric
          )
          Divider()
        }

        GoalProgressChartView(detail: detail, breakdown: breakdown)

        Divider()

        ScoreDifferenceChartView(detail: detail, breakdown: breakdown)

        Text("Conversion and turnovers are inferred from which team scored after each centre pass. "
          + "Goal time starts at the previous goal or quarter start.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding()
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
  }

  package init(detail: GameAnalysis, breakdown: GameAnalysisBreakdown = .wholeGame) {
    self.detail = detail
    _breakdown = State(initialValue: breakdown)
  }
}

private struct StatisticComparisonRow: View {
  var teamAName: String
  var teamAColor: Color
  var teamAStatistics: TeamGameStatistics
  var teamBName: String
  var teamBColor: Color
  var teamBStatistics: TeamGameStatistics
  var metric: GameStatistic

  var body: some View {
    VStack(spacing: 8) {
      Text(metric.rawValue)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      HStack(spacing: 16) {
        Text(metric.text(teamAStatistics))
          .frame(maxWidth: .infinity)

        Divider()
          .frame(height: 24)

        Text(metric.text(teamBStatistics))
          .frame(maxWidth: .infinity)
      }
      .font(.system(.title3, design: .rounded, weight: .bold))
      .monospacedDigit()

      StatisticComparisonBar(
        teamAFraction: metric.teamAFraction(teamA: teamAStatistics, teamB: teamBStatistics),
        teamAColor: teamAColor,
        teamBColor: teamBColor
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(metric.rawValue), \(teamAName), \(metric.accessibleText(teamAStatistics)), "
      + "\(teamBName), \(metric.accessibleText(teamBStatistics))")
  }
}

private struct StatisticComparisonBar: View {
  var teamAFraction: Double?
  var teamAColor: Color
  var teamBColor: Color

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Rectangle().fill(.quaternary)
        if let teamAFraction {
          HStack(spacing: 0) {
            teamAColor.frame(width: geometry.size.width * teamAFraction)
            teamBColor.frame(width: geometry.size.width * (1 - teamAFraction))
          }
        }
      }
      .clipShape(Capsule())
    }
    .frame(height: 8)
    .accessibilityHidden(true)
  }
}

private struct TeamStatisticsHeader: View {
  var color: Color
  var isTrailing = false
  var name: String

  var body: some View {
    HStack(spacing: 8) {
      if isTrailing {
        Text(name)
      }

      Circle()
        .fill(color)
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)

      if !isTrailing {
        Text(name)
      }
    }
    .font(.headline)
    .lineLimit(2)
    .multilineTextAlignment(isTrailing ? .trailing : .leading)
    .frame(maxWidth: .infinity, alignment: isTrailing ? .trailing : .leading)
  }
}

#Preview("Game statistics") {
  GameStatisticsView(detail: CompletedGameDetail.previewCompleted.analysis)
    .padding()
}

#Preview("Empty statistics") {
  var analysis = CompletedGameDetail.previewNoGoals.analysis
  analysis.periods = CompletedGameDetail.previewCompleted.periods
  return GameStatisticsView(detail: analysis)
    .padding()
}

#Preview("Quarter comparison with unavailable centre passes") {
  var analysis = CompletedGameDetail.previewCompleted.analysis
  analysis.statisticsByPeriod[1] = CompletedGameStatistics(
    teamA: TeamGameStatistics(averageTimeToGoalSeconds: 20.25, biggestLead: 4, longestScoringRun: 2),
    teamB: TeamGameStatistics(averageTimeToGoalSeconds: 45.75, biggestLead: 1, longestScoringRun: 3)
  )
  return ScrollView {
    GameStatisticsView(detail: analysis, breakdown: .period(1))
      .padding()
  }
}
