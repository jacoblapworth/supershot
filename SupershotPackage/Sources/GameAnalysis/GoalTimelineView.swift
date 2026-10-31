import AppUI
import Database
import GameCore
import LocationClient
import PaywallFeature
import PreviewSupport
import SharedModels
import SwiftUI
import UI

package struct GoalTimelineView: View {
  package var teamABibColor: Color
  package var teamAName: String
  package var teamBBibColor: Color
  package var teamBName: String
  package var timeline: GoalTimeline
  package var teamAOnLeft = true

  package var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      GoalTimelineLegend(
        teamABibColor: teamABibColor,
        teamAName: teamAName,
        teamBBibColor: teamBBibColor,
        teamBName: teamBName,
        teamAOnLeft: teamAOnLeft
      )

      LazyVStack(spacing: 20) {
        ForEach(timeline.quarters) { quarter in
          GoalTimelineQuarterView(
            quarter: quarter,
            teamABibColor: teamABibColor,
            teamAName: teamAName,
            teamBBibColor: teamBBibColor,
            teamBName: teamBName,
            teamAOnLeft: teamAOnLeft
          )
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  package init(
    teamABibColor: Color, teamAName: String, teamBBibColor: Color, teamBName: String,
    timeline: GoalTimeline, teamAOnLeft: Bool = true
  ) {
    self.teamABibColor = teamABibColor
    self.teamAName = teamAName
    self.teamBBibColor = teamBBibColor
    self.teamBName = teamBName
    self.timeline = timeline
    self.teamAOnLeft = teamAOnLeft
  }
}

private struct GoalTimelineLegend: View {
  var teamABibColor: Color
  var teamAName: String
  var teamBBibColor: Color
  var teamBName: String
  var teamAOnLeft: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      teamLabel(
        name: teamAOnLeft ? teamAName : teamBName,
        color: teamAOnLeft ? teamABibColor : teamBBibColor,
        isLeft: true
      )
      teamLabel(
        name: teamAOnLeft ? teamBName : teamAName,
        color: teamAOnLeft ? teamBBibColor : teamABibColor,
        isLeft: false
      )
    }
    .padding(.horizontal, 4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(teamAOnLeft ? teamAName : teamBName) is on the left. "
        + "\(teamAOnLeft ? teamBName : teamAName) is on the right."
    )
  }

  private func teamLabel(name: String, color: Color, isLeft: Bool) -> some View {
    HStack(alignment: .top, spacing: 8) {
      if isLeft {
        teamColor(color)
      }
      VStack(alignment: isLeft ? .leading : .trailing, spacing: 2) {
        Text(name)
          .font(.subheadline.weight(.semibold))
          .multilineTextAlignment(isLeft ? .leading : .trailing)
          .fixedSize(horizontal: false, vertical: true)
        Text(isLeft ? "Left" : "Right")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if !isLeft {
        teamColor(color)
      }
    }
    .frame(maxWidth: .infinity, alignment: isLeft ? .leading : .trailing)
  }

  private func teamColor(_ color: Color) -> some View {
    Circle()
      .fill(color)
      .frame(width: 12, height: 12)
      .padding(.top, 3)
      .accessibilityHidden(true)
  }
}

private struct GoalTimelineQuarterView: View {
  var quarter: GoalTimelineQuarter
  var teamABibColor: Color
  var teamAName: String
  var teamBBibColor: Color
  var teamBName: String
  var teamAOnLeft: Bool

  var body: some View {
    VStack(spacing: 12) {
      GoalTimelineQuarterHeader(
        quarter: quarter,
        teamABibColor: teamABibColor,
        teamAName: teamAName,
        teamBBibColor: teamBBibColor,
        teamBName: teamBName,
        teamAOnLeft: teamAOnLeft
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
              teamBName: teamBName,
              teamAOnLeft: teamAOnLeft
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
  var teamABibColor: Color
  var teamAName: String
  var teamBBibColor: Color
  var teamBName: String
  var teamAOnLeft: Bool

  var body: some View {
    HStack(spacing: 12) {
      score(
        teamAOnLeft ? quarter.teamAQuarterScore : quarter.teamBQuarterScore,
        color: teamAOnLeft ? teamABibColor : teamBBibColor
      )

      Spacer(minLength: 0)

      VStack(spacing: 2) {
        Text("Quarter \(quarter.period)")
          .font(.headline)
        Text("Quarter score")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)

      score(
        teamAOnLeft ? quarter.teamBQuarterScore : quarter.teamAQuarterScore,
        color: teamAOnLeft ? teamBBibColor : teamABibColor
      )
    }
    .padding(12)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Quarter \(quarter.period) score, \(teamAName) \(quarter.teamAQuarterScore), "
        + "\(teamBName) \(quarter.teamBQuarterScore)"
    )
  }

  private func score(_ score: Int, color: Color) -> some View {
    Text("\(score)")
      .font(.title3.bold())
      .monospacedDigit()
      .foregroundStyle(color)
      .frame(minWidth: 38, minHeight: 34)
      .background(
        color.opacity(0.12),
        in: RoundedRectangle(cornerRadius: 9)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 9)
          .stroke(color.opacity(0.45))
      }
  }
}

private struct GoalTimelineRow: View {
  var goal: GoalTimelineItem
  var teamAName: String
  var teamBName: String
  var teamAOnLeft: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      if isOnLeft {
        eventCard
        marker
        Color.clear.frame(maxWidth: .infinity)
      } else {
        Color.clear.frame(maxWidth: .infinity)
        marker
        eventCard
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

  private var isOnLeft: Bool {
    switch goal.scoringTeamSide {
    case .teamA: teamAOnLeft
    case .teamB: !teamAOnLeft
    case .unknown: false
    }
  }

  private var eventCard: some View {
    VStack(
      alignment: isOnLeft ? .trailing : .leading,
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

      Text(
        "Match \(teamAOnLeft ? goal.teamAScore : goal.teamBScore)–\(teamAOnLeft ? goal.teamBScore : goal.teamAScore)"
      )
      .font(.caption.weight(.semibold))
      .monospacedDigit()
    }
    .multilineTextAlignment(isOnLeft ? .trailing : .leading)
    .padding(10)
    .frame(
      maxWidth: .infinity,
      alignment: isOnLeft ? .trailing : .leading
    )
    .background(
      goal.scoringTeamBibColor.opacity(0.12),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(goal.scoringTeamBibColor.opacity(0.5))
    }
  }

  private var marker: some View {
    Image(systemName: "volleyball.fill")
      .font(.caption.weight(.semibold))
      .foregroundStyle(goal.scoringTeamBibColor)
      .frame(width: 28, height: 28)
      .background(.background, in: Circle())
      .overlay {
        Circle()
          .stroke(goal.scoringTeamBibColor.opacity(0.5))
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
    teamABibColor: detail.teamABibColor,
    teamAName: detail.teamAName,
    teamBBibColor: detail.teamBBibColor,
    teamBName: detail.teamBName,
    timeline: detail.goalTimeline
  )
  .padding()
}

#Preview("Empty goal timeline") {
  let detail = CompletedGameDetail.previewNoGoals
  GoalTimelineView(
    teamABibColor: detail.teamABibColor,
    teamAName: detail.teamAName,
    teamBBibColor: detail.teamBBibColor,
    teamBName: detail.teamBName,
    timeline: detail.goalTimeline
  )
  .padding()
}

#Preview("Goal timeline accessibility text") {
  let detail = CompletedGameDetail.previewCompleted
  ScrollView {
    GoalTimelineView(
      teamABibColor: detail.teamABibColor,
      teamAName: detail.teamAName,
      teamBBibColor: detail.teamBBibColor,
      teamBName: detail.teamBName,
      timeline: detail.goalTimeline
    )
    .padding()
  }
  .environment(\.dynamicTypeSize, .accessibility3)
}
