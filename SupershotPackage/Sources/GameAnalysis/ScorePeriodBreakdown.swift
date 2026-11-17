import AppUI
import Database
import GameCore
import LocationClient
import PaywallFeature
import PreviewSupport
import SharedModels
import SwiftUI
import UI

package struct ScorePeriodBreakdown: View {
  var periods: [GoalTimelinePeriod]
  var teamABibColor: Color
  var teamAName: String
  var teamBBibColor: Color
  var teamBName: String

  private var periodTitle: String {
    GamePeriodFormat.title(for: periods.count).lowercased()
  }

  package var body: some View {
    ViewThatFits(in: .horizontal) {
      grid.fixedSize(horizontal: true, vertical: false)
      ScrollView(.horizontal) { grid }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Points by \(periodTitle)")
  }

  private var grid: some View {
    Grid(horizontalSpacing: 12, verticalSpacing: 6) {
      GridRow {
        Color.clear
          .frame(width: 0, height: 0)
          .gridCellUnsizedAxes([.horizontal, .vertical])
        ForEach(sortedQuarters) {
          Text("\($0.period)")
        }
        Text("T")
          .accessibilityLabel("Total points")
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)

      scoreRow(name: teamAName, color: teamABibColor) { $0.teamAQuarterScore }
      Divider()
      scoreRow(name: teamBName, color: teamBBibColor) { $0.teamBQuarterScore }
    }
  }

  private var sortedQuarters: [GoalTimelinePeriod] {
    periods.sorted(using: KeyPathComparator(\.period))
  }

  private func scoreRow(
    name: String,
    color: Color,
    score: @escaping (GoalTimelinePeriod) -> Int
  ) -> some View {
    let total = periods.reduce(0) { $0 + score($1) }

    return GridRow {
      HStack(spacing: 5) {
        Circle()
          .fill(color)
          .frame(width: 8, height: 8)
          .accessibilityHidden(true)
        Text(name)
          .lineLimit(1)
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .gridColumnAlignment(.leading)

      ForEach(sortedQuarters) { quarter in
        Text("\(score(quarter))")
          .font(.system(.caption, design: .rounded, weight: .semibold))
          .accessibilityLabel("\(name), \(periodTitle) \(quarter.period), \(score(quarter))")
      }

      Text("\(total)")
        .font(.system(.caption, design: .rounded, weight: .bold))
        .accessibilityLabel("\(name), total points, \(total)")
    }
  }
}

#Preview("Game overview") {
  let preview = CompletedGameDetail.previewCompleted
  GroupBox {
    ScorePeriodBreakdown(
      periods: preview.goalTimeline.quarters,
      teamABibColor: preview.teamABibColor,
      teamAName: preview.teamAName,
      teamBBibColor: preview.teamBBibColor,
      teamBName: preview.teamBName
    )
  }
}
