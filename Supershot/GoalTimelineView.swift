import SwiftUI

struct GoalTimelineView: View {
  var detail: CompletedGameDetail

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Goal timeline")
        .font(.title2.bold())

      if detail.goals.isEmpty {
        ContentUnavailableView(
          "No goals recorded",
          systemImage: "soccerball",
          description: Text("This game finished without a recorded goal.")
        )
        .frame(maxWidth: .infinity)
      } else {
        LazyVStack(spacing: 12) {
          ForEach(detail.goals) { goal in
            GoalTimelineRow(
              goal: goal,
              teamAName: detail.teamAName,
              teamBName: detail.teamBName
            )
          }
        }
      }
    }
  }
}

private struct GoalTimelineRow: View {
  var goal: GoalTimelineItem
  var teamAName: String
  var teamBName: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "soccerball")
        .font(.title3)
        .foregroundStyle(Color(teamHex: goal.scoringTeamColorHex))
        .frame(width: 28, height: 28)
        .background(Color(teamHex: goal.scoringTeamColorHex).opacity(0.12), in: Circle())

      VStack(alignment: .leading, spacing: 5) {
        Text(goal.scoringTeamName)
          .font(.headline)
          .lineLimit(2)

        Text("Quarter \(goal.period) · \(formattedTime(goal.clockSecondsRemaining)) remaining")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Text("\(teamAName) \(goal.teamAScore) – \(goal.teamBScore) \(teamBName)")
          .font(.subheadline.weight(.semibold))
          .lineLimit(2)

        Text("+\(goal.points) \(goal.points == 1 ? "point" : "points")")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .combine)
  }

  private func formattedTime(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let seconds = seconds % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
  }
}

#Preview("Goal timeline") {
  GoalTimelineView(detail: .previewCompleted)
    .padding()
}

#Preview("Empty goal timeline") {
  GoalTimelineView(detail: .previewNoGoals)
    .padding()
}
