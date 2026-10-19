import Charts
import Database
import GameCore
import PreviewSupport
import Styleguide
import SwiftUI
import WidgetSupport

package struct ScoreDifferenceChartView: View {
  package var detail: GameAnalysis
  package var breakdown = GameAnalysisBreakdown.wholeGame

  package var body: some View {
    ScoreDifferenceChart(
      series: ScoreDifferenceSeries(analysis: detail, breakdown: breakdown),
      breakdown: breakdown,
      teamAName: detail.teamAName, teamAColor: detail.teamABibColor,
      teamBName: detail.teamBName, teamBColor: detail.teamBBibColor
    )
  }
}

private struct ScoreDifferenceChart: View {
  let series: ScoreDifferenceSeries
  let breakdown: GameAnalysisBreakdown
  let teamAName: String
  let teamAColor: Color
  let teamBName: String
  let teamBColor: Color
  @State private var selectedMoment: ScoreDifferenceSeries.Point?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(spacing: 4) {
        Text("Score difference")
          .font(.subheadline.weight(.semibold))
        Text(breakdown.title)
          .font(.caption)
      }
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)

      if series.moments.isEmpty {
        ContentUnavailableView(
          "No goals recorded in \(breakdown.title)", systemImage: "chart.xyaxis.line",
          description: Text("Score difference will appear here once goals are recorded.")
        )
        .frame(maxWidth: .infinity)
      } else {
        Chart {
          RuleMark(y: .value("Scores level", 0))
            .foregroundStyle(Color.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1.5))

          ForEach(series.periodEndOffsets, id: \.self) { offset in
            RuleMark(x: .value("Quarter boundary", offset))
              .foregroundStyle(Color.secondary.opacity(0.5))
              .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
          }

          ForEach(series.points) { point in
            LineMark(
              x: .value("Playing time", point.elapsedSeconds),
              y: .value("Difference", point.difference)
            )
            .foregroundStyle(Color.primary)
            .interpolationMethod(.stepEnd)
          }

          ForEach(series.moments) { moment in
            PointMark(
              x: .value("Playing time", moment.elapsedSeconds),
              y: .value("Difference", moment.difference)
            )
            .foregroundStyle(
              moment.difference > 0 ? teamAColor : moment.difference < 0 ? teamBColor : .primary
            )
            .symbolSize(20)
          }

          if let selectedMoment {
            RuleMark(x: .value("Selected time", selectedMoment.elapsedSeconds))
              .foregroundStyle(Color.primary.opacity(0.5))
          }
        }
        .chartXScale(domain: 0...series.duration)
        .chartYScale(domain: -series.extent...series.extent)
        .chartXAxisLabel("Playing time")
        .chartYAxisLabel("Points")
        .chartXAxis {
          AxisMarks(values: .automatic(desiredCount: 5)) { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
              if let seconds = value.as(Int.self) {
                Text(elapsedTime(seconds))
              }
            }
          }
        }
        .chartYAxis {
          AxisMarks(position: .leading, values: [-series.extent, 0, series.extent]) { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
              if let points = value.as(Int.self) {
                Text(points, format: .number.sign(strategy: .always(includingZero: false)))
              }
            }
          }
        }
        .frame(height: 220)
        .chartOverlay { proxy in
          GeometryReader { geometry in
            Rectangle()
              .fill(.clear)
              .contentShape(Rectangle())
              .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                  .onChanged { value in
                    selectionChanged(at: value.location, proxy: proxy, geometry: geometry)
                  }
                  .onEnded { _ in selectedMoment = nil }
              )
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(breakdown.title) score difference chart")
        .accessibilityValue(
          Text(
            "\(teamAName) \(series.moments.last?.teamAScore ?? 0), \(teamBName) \(series.moments.last?.teamBScore ?? 0). \(scoreDifferenceLeadDescription(series.moments.last?.difference ?? 0, teamAName: teamAName, teamBName: teamBName))"
          )
        )
        .accessibilityIdentifier("gameAnalysis.scoreDifference")

        if let selectedMoment {
          ScoreDifferenceInspection(
            moment: selectedMoment, teamAName: teamAName, teamBName: teamBName
          )
        } else {
          Text("Press and hold the chart to inspect the score.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        Label {
          Text("Positive: \(teamAName) leads")
        } icon: {
          Image(systemName: "plus.circle.fill").foregroundStyle(teamAColor)
        }
        Label {
          Text("Negative: \(teamBName) leads")
        } icon: {
          Image(systemName: "minus.circle.fill").foregroundStyle(teamBColor)
        }
        if breakdown == .wholeGame {
          Text("0 means scores level. Dashed lines mark quarter boundaries.")
            .foregroundStyle(.secondary)
        } else {
          Text("0 means scores level in this quarter.")
            .foregroundStyle(.secondary)
        }
      }
      .font(.caption)
      .fixedSize(horizontal: false, vertical: true)
    }
    .onChange(of: series) { selectedMoment = nil }
    .onChange(of: breakdown) { selectedMoment = nil }
  }

  private func selectionChanged(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
    guard let plotFrame = proxy.plotFrame else {
      selectedMoment = nil
      return
    }
    let plotArea = geometry[plotFrame]
    guard plotArea.contains(location),
      let seconds = proxy.value(atX: location.x - plotArea.minX, as: Int.self)
    else {
      selectedMoment = nil
      return
    }
    selectedMoment = series.nearestMoment(to: seconds)
  }
}

private struct ScoreDifferenceInspection: View {
  let moment: ScoreDifferenceSeries.Point
  let teamAName: String
  let teamBName: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Q\(moment.period) · \(elapsedTime(moment.periodElapsedSeconds))")
        .foregroundStyle(.secondary)
      Text("\(teamAName) \(moment.teamAScore) – \(moment.teamBScore) \(teamBName)")
        .monospacedDigit()
      Text(scoreDifferenceLeadDescription(
        moment.difference, teamAName: teamAName, teamBName: teamBName))
    }
    .font(.caption.weight(.medium))
    .fixedSize(horizontal: false, vertical: true)
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background, in: RoundedRectangle(cornerRadius: 8))
  }
}

private func elapsedTime(_ seconds: Int) -> String {
  Duration.seconds(max(seconds, 0)).formatted(.time(pattern: .minuteSecond))
}

private func scoreDifferenceLeadDescription(
  _ difference: Int, teamAName: String, teamBName: String
) -> LocalizedStringResource {
  if difference == 0 { return "Scores level" }
  let name = difference > 0 ? teamAName : teamBName
  if abs(difference) == 1 { return "\(name) leads by 1 point" }
  return "\(name) leads by \(abs(difference)) points"
}

#Preview("Score difference") {
  ScoreDifferenceChartView(detail: CompletedGameDetail.previewCompleted.analysis)
    .padding()
}

#Preview("Empty score difference") {
  ScoreDifferenceChartView(detail: CompletedGameDetail.previewNoGoals.analysis)
    .padding()
}

#Preview("Quarter score difference") {
  ScoreDifferenceChartView(
    detail: CompletedGameDetail.previewCompleted.analysis, breakdown: .period(2)
  )
  .padding()
}

#Preview("Weighted goals, lead changes and a tie") {
  ScoreDifferenceChartView(
    detail: scoreDifferencePreview(scores: [(2, 0), (2, 1), (2, 3), (3, 3)])
  )
  .padding()
}

#Preview("One-sided live game") {
  var analysis = scoreDifferencePreview(scores: [(0, 1), (0, 3), (0, 4)])
  analysis.isComplete = false
  analysis.teamBName = "A visiting team with a long name"
  return ScoreDifferenceChartView(detail: analysis)
    .padding()
}

private func scoreDifferencePreview(scores: [(Int, Int)]) -> GameAnalysis {
  var analysis = CompletedGameDetail.previewCompleted.analysis
  guard let period = analysis.periods.first else { return analysis }
  let goals = analysis.goalTimeline.quarters.reversed().flatMap { $0.goals.reversed() }
  let moments = zip(goals, scores).enumerated().map { index, pair in
    GoalTimelineItem(
      clockSecondsRemaining: max(period.durationSeconds - (index + 1) * 60, 0),
      id: pair.0.id, period: period.number, points: pair.0.points,
      scoringTeamName: pair.0.scoringTeamName, scoringTeamSide: pair.0.scoringTeamSide,
      teamAScore: pair.1.0, teamBScore: pair.1.1
    )
  }
  analysis.goalTimeline = GoalTimeline(quarters: [
    GoalTimelineQuarter(
      goals: moments.reversed(), period: period.number,
      teamAQuarterScore: scores.last?.0 ?? 0, teamBQuarterScore: scores.last?.1 ?? 0
    )
  ])
  return analysis
}
