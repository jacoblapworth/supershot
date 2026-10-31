import AppUI
import Database
import GameCore
import LocationClient
import PaywallFeature
import PreviewSupport
import SharedModels
import SwiftUI
import UI

package struct GameOverviewView: View {
  package var detail: CompletedGameDetail

  package var body: some View {
    VStack(spacing: 20) {
      VStack(spacing: 8) {
        Label("Full time", systemImage: "flag.checkered")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)

        Text(detail.resultTitle)
          .font(.title2.bold())
          .multilineTextAlignment(.center)
      }

      ScoreboardView(
        left: .init(name: detail.teamAName, color: detail.teamABibColor, score: detail.teamAScore),
        right: .init(name: detail.teamBName, color: detail.teamBBibColor, score: detail.teamBScore)
      )

      VStack(spacing: 20) {
        QuarterScoreBreakdown(
          quarters: detail.goalTimeline.quarters,
          teamABibColor: detail.teamABibColor,
          teamAName: detail.teamAName,
          teamBBibColor: detail.teamBBibColor,
          teamBName: detail.teamBName
        )

        Divider()

        VStack(alignment: .leading, spacing: 8) {
          if let scheduledAt = detail.scheduledAt {
            LabeledContent("Scheduled") {
              Text(scheduledAt.formatted(date: .abbreviated, time: .shortened))
            }
          }
          if let court = detail.court {
            LabeledContent("Court", value: court)
          }
          LabeledContent("Started") {
            Text(detail.startedAt.formatted(date: .abbreviated, time: .shortened))
          }
          LabeledContent("Finished") {
            Text(detail.endedAt.formatted(date: .abbreviated, time: .shortened))
          }
          LabeledContent("Timing") {
            Text(detail.timingSummary)
              .multilineTextAlignment(.trailing)
          }
        }
        .font(.subheadline)
      }
      .padding()
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    .frame(maxWidth: .infinity)
  }

  package init(detail: CompletedGameDetail) {
    self.detail = detail
  }
}

private struct QuarterScoreBreakdown: View {
  var quarters: [GoalTimelineQuarter]
  var teamABibColor: Color
  var teamAName: String
  var teamBBibColor: Color
  var teamBName: String

  var body: some View {
    VStack(spacing: 8) {
      Text("Points by quarter")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      VStack(spacing: 6) {
        HStack(spacing: 12) {
          teamName(teamAName, color: teamABibColor, alignment: .leading)
          Text("Quarter")
            .frame(width: 64)
          teamName(teamBName, color: teamBBibColor, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

        ForEach(quarters.sorted(using: KeyPathComparator(\.period))) { quarter in
          HStack(spacing: 12) {
            Text("\(quarter.teamAQuarterScore)")
              .frame(maxWidth: .infinity, alignment: .leading)

            Text("Q\(quarter.period)")
              .frame(width: 64)
              .foregroundStyle(.secondary)

            Text("\(quarter.teamBQuarterScore)")
              .frame(maxWidth: .infinity, alignment: .trailing)
          }
          .font(.system(.body, design: .rounded, weight: .semibold))
          .monospacedDigit()
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(
            "Quarter \(quarter.period), \(teamAName) \(quarter.teamAQuarterScore), "
              + "\(teamBName) \(quarter.teamBQuarterScore)"
          )
        }
      }
    }
  }

  private func teamName(
    _ name: String,
    color: Color,
    alignment: Alignment
  ) -> some View {
    HStack(spacing: 5) {
      if alignment == .trailing {
        Spacer(minLength: 0)
      }
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
      Text(name)
        .lineLimit(1)
      if alignment == .leading {
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, alignment: alignment)
  }
}

#Preview("Game overview") {
  GameOverviewView(detail: .previewCompleted)
    .padding()
}

#Preview("Drawn game overview") {
  GameOverviewView(detail: .previewDraw)
    .padding()
}
