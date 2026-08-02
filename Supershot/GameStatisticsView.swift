import SwiftUI

struct GameStatisticsView: View {
  var detail: CompletedGameDetail

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Statistics")
        .font(.title2.bold())

      VStack(spacing: 16) {
        HStack(alignment: .top, spacing: 16) {
          TeamStatisticsHeader(
            colorHex: detail.teamABibColorHex,
            name: detail.teamAName
          )

          TeamStatisticsHeader(
            colorHex: detail.teamBBibColorHex,
            isTrailing: true,
            name: detail.teamBName
          )
        }

        Divider()

        StatisticComparisonRow(
          teamAName: detail.teamAName,
          teamAValue: centrePassConversion(detail.statistics.teamA),
          teamBName: detail.teamBName,
          teamBValue: centrePassConversion(detail.statistics.teamB),
          title: "Centre pass conversion"
        )

        Divider()

        StatisticComparisonRow(
          teamAName: detail.teamAName,
          teamAValue: averageTimeToGoal(detail.statistics.teamA),
          teamBName: detail.teamBName,
          teamBValue: averageTimeToGoal(detail.statistics.teamB),
          title: "Avg time to goal"
        )

        Divider()

        StatisticComparisonRow(
          teamAName: detail.teamAName,
          teamAValue: inferredTurnovers(detail.statistics.teamA),
          teamBName: detail.teamBName,
          teamBValue: inferredTurnovers(detail.statistics.teamB),
          title: "Turnovers"
        )

        Text(
          "Conversion and turnovers are inferred from which team scored after each centre pass. "
            + "Goal time starts at the previous goal or quarter start."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding()
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
  }

  private func averageTimeToGoal(_ statistics: TeamGameStatistics) -> String {
    guard let average = statistics.averageTimeToGoalSeconds else { return "—" }
    let seconds = max(Int(average.rounded()), 0)
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
  }

  private func centrePassConversion(_ statistics: TeamGameStatistics) -> String {
    guard
      let centrePass = statistics.centrePass,
      centrePass.opportunities > 0
    else { return "—" }
    let percentage = Int(
      (Double(centrePass.conversions) / Double(centrePass.opportunities) * 100).rounded()
    )
    return "\(centrePass.conversions)/\(centrePass.opportunities) · \(percentage)%"
  }

  private func inferredTurnovers(_ statistics: TeamGameStatistics) -> String {
    statistics.centrePass.map { "\($0.inferredTurnovers)" } ?? "—"
  }
}

private struct StatisticComparisonRow: View {
  var teamAName: String
  var teamAValue: String
  var teamBName: String
  var teamBValue: String
  var title: String

  var body: some View {
    VStack(spacing: 8) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      HStack(spacing: 16) {
        Text(teamAValue)
          .frame(maxWidth: .infinity)

        Divider()
          .frame(height: 24)

        Text(teamBValue)
          .frame(maxWidth: .infinity)
      }
      .font(.system(.title3, design: .rounded, weight: .bold))
      .monospacedDigit()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(title), \(teamAName), \(accessible(teamAValue)), "
        + "\(teamBName), \(accessible(teamBValue))"
    )
  }

  private func accessible(_ value: String) -> String {
    value == "—" ? "unavailable" : value
  }
}

private struct TeamStatisticsHeader: View {
  var colorHex: String
  var isTrailing = false
  var name: String

  var body: some View {
    HStack(spacing: 8) {
      if isTrailing {
        Text(name)
      }

      Circle()
        .fill(Color(teamHex: colorHex))
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
  GameStatisticsView(detail: .previewCompleted)
    .padding()
}
