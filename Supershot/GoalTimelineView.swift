import SwiftUI

struct GoalTimelineView: View {
  var teamABibColorHex: String
  var teamAName: String
  var teamBBibColorHex: String
  var teamBName: String
  var timeline: GoalTimeline

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Goal timeline")
        .font(.title2.bold())

      GoalTimelineLegend(
        teamABibColorHex: teamABibColorHex,
        teamAName: teamAName,
        teamBBibColorHex: teamBBibColorHex,
        teamBName: teamBName
      )

      LazyVStack(spacing: 20) {
        ForEach(timeline.quarters) { quarter in
          GoalTimelineQuarterView(
            quarter: quarter,
            teamABibColorHex: teamABibColorHex,
            teamAName: teamAName,
            teamBBibColorHex: teamBBibColorHex,
            teamBName: teamBName
          )
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct GoalTimelineLegend: View {
  var teamABibColorHex: String
  var teamAName: String
  var teamBBibColorHex: String
  var teamBName: String

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      HStack(alignment: .top, spacing: 8) {
        teamColor(teamABibColorHex)
        VStack(alignment: .leading, spacing: 2) {
          Text(teamAName)
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
          Text("Left")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .trailing, spacing: 2) {
          Text(teamBName)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
          Text("Right")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        teamColor(teamBBibColorHex)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, 4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(teamAName) is on the left. \(teamBName) is on the right."
    )
  }

  private func teamColor(_ colorHex: String) -> some View {
    Circle()
      .fill(Color(teamHex: colorHex))
      .frame(width: 12, height: 12)
      .padding(.top, 3)
      .accessibilityHidden(true)
  }
}

private struct GoalTimelineQuarterView: View {
  var quarter: GoalTimelineQuarter
  var teamABibColorHex: String
  var teamAName: String
  var teamBBibColorHex: String
  var teamBName: String

  var body: some View {
    VStack(spacing: 12) {
      GoalTimelineQuarterHeader(
        quarter: quarter,
        teamABibColorHex: teamABibColorHex,
        teamAName: teamAName,
        teamBBibColorHex: teamBBibColorHex,
        teamBName: teamBName
      )

      if quarter.goals.isEmpty {
        Text("No goals this quarter")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
        .accessibilityLabel("Quarter \(quarter.period), no goals recorded")
      } else {
        LazyVStack(spacing: 12) {
          ForEach(quarter.goals) { goal in
            GoalTimelineRow(
              goal: goal,
              teamAName: teamAName,
              teamBName: teamBName
            )
          }
        }
        .background(alignment: .center) {
          Rectangle()
            .fill(.quaternary)
            .frame(width: 2)
            .padding(.vertical, 14)
            .accessibilityHidden(true)
        }
      }
    }
  }
}

private struct GoalTimelineQuarterHeader: View {
  var quarter: GoalTimelineQuarter
  var teamABibColorHex: String
  var teamAName: String
  var teamBBibColorHex: String
  var teamBName: String

  var body: some View {
    HStack(spacing: 12) {
      score(quarter.teamAQuarterScore, colorHex: teamABibColorHex)

      Spacer(minLength: 0)

      VStack(spacing: 2) {
      Text("Quarter \(quarter.period)")
          .font(.headline)
        Text("Quarter score")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)

      score(quarter.teamBQuarterScore, colorHex: teamBBibColorHex)
    }
    .padding(12)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Quarter \(quarter.period) score, \(teamAName) \(quarter.teamAQuarterScore), "
        + "\(teamBName) \(quarter.teamBQuarterScore)"
    )
  }

  private func score(_ score: Int, colorHex: String) -> some View {
    Text("\(score)")
      .font(.title3.bold())
      .monospacedDigit()
      .foregroundStyle(Color(teamHex: colorHex))
      .frame(minWidth: 38, minHeight: 34)
      .background(
        Color(teamHex: colorHex).opacity(0.12),
        in: RoundedRectangle(cornerRadius: 9)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 9)
          .stroke(Color(teamHex: colorHex).opacity(0.45))
      }
  }
}

private struct GoalTimelineRow: View {
  var goal: GoalTimelineItem
  var teamAName: String
  var teamBName: String

  var body: some View {
    Group {
      switch goal.scoringTeamSide {
      case .teamA:
        HStack(alignment: .top, spacing: 8) {
          eventCard
          marker
          Color.clear
            .frame(maxWidth: .infinity)
        }

      case .teamB:
        HStack(alignment: .top, spacing: 8) {
          Color.clear
            .frame(maxWidth: .infinity)
          marker
          eventCard
        }

      case .unknown:
        HStack(alignment: .top, spacing: 8) {
          Color.clear
            .frame(maxWidth: .infinity)
          marker
          eventCard
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(goal.scoringTeamName), \(goal.points) "
        + "\(goal.points == 1 ? "point" : "points"), "
        + "\(formattedTime(goal.clockSecondsRemaining)) remaining, "
        + "match score \(teamAName) \(goal.teamAScore), \(teamBName) \(goal.teamBScore)"
    )
  }

  private var eventCard: some View {
    VStack(
      alignment: goal.scoringTeamSide == .teamA ? .trailing : .leading,
      spacing: 5
    ) {
      Text(goal.scoringTeamName)
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)

      Text("+\(goal.points) \(goal.points == 1 ? "point" : "points")")
        .font(.headline)

      Text("\(formattedTime(goal.clockSecondsRemaining)) remaining")
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()

      Text("Match \(goal.teamAScore)–\(goal.teamBScore)")
        .font(.caption.weight(.semibold))
        .monospacedDigit()
    }
    .multilineTextAlignment(goal.scoringTeamSide == .teamA ? .trailing : .leading)
    .padding(10)
    .frame(
      maxWidth: .infinity,
      alignment: goal.scoringTeamSide == .teamA ? .trailing : .leading
    )
    .background(
      Color(teamHex: goal.scoringTeamBibColorHex).opacity(0.12),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color(teamHex: goal.scoringTeamBibColorHex).opacity(0.5))
    }
  }

  private var marker: some View {
    Image(systemName: "volleyball.fill")
      .font(.caption.weight(.semibold))
      .foregroundStyle(Color(teamHex: goal.scoringTeamBibColorHex))
      .frame(width: 28, height: 28)
      .background(.background, in: Circle())
      .overlay {
        Circle()
          .stroke(Color(teamHex: goal.scoringTeamBibColorHex).opacity(0.5))
      }
      .accessibilityHidden(true)
  }

  private func formattedTime(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let seconds = seconds % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
  }
}

#Preview("Goal timeline") {
  let detail = CompletedGameDetail.previewCompleted
  GoalTimelineView(
    teamABibColorHex: detail.teamABibColorHex,
    teamAName: detail.teamAName,
    teamBBibColorHex: detail.teamBBibColorHex,
    teamBName: detail.teamBName,
    timeline: detail.goalTimeline
  )
  .padding()
}

#Preview("Empty goal timeline") {
  let detail = CompletedGameDetail.previewNoGoals
  GoalTimelineView(
    teamABibColorHex: detail.teamABibColorHex,
    teamAName: detail.teamAName,
    teamBBibColorHex: detail.teamBBibColorHex,
    teamBName: detail.teamBName,
    timeline: detail.goalTimeline
  )
  .padding()
}

#Preview("Goal timeline accessibility text") {
  let detail = CompletedGameDetail.previewCompleted
  ScrollView {
    GoalTimelineView(
      teamABibColorHex: detail.teamABibColorHex,
      teamAName: detail.teamAName,
      teamBBibColorHex: detail.teamBBibColorHex,
      teamBName: detail.teamBName,
      timeline: detail.goalTimeline
    )
    .padding()
  }
  .environment(\.dynamicTypeSize, .accessibility3)
}
