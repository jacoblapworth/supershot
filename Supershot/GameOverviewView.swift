import SwiftUI

struct GameOverviewView: View {
  var detail: CompletedGameDetail

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "flag.checkered")
        .font(.system(size: 40, weight: .semibold))
        .foregroundStyle(.secondary)

      Text(detail.resultTitle)
        .font(.largeTitle.bold())
        .multilineTextAlignment(.center)

      HStack(alignment: .top, spacing: 16) {
        GameDetailScore(
          alignment: .leading,
          colorHex: detail.teamABibColorHex,
          name: detail.teamAName,
          score: detail.teamAScore
        )

        Text("–")
          .font(.title.bold())
          .foregroundStyle(.secondary)
          .padding(.top, 36)

        GameDetailScore(
          alignment: .trailing,
          colorHex: detail.teamBBibColorHex,
          name: detail.teamBName,
          score: detail.teamBScore
        )
      }

      QuarterScoreBreakdown(
        quarters: detail.goalTimeline.quarters,
        teamABibColorHex: detail.teamABibColorHex,
        teamAName: detail.teamAName,
        teamBBibColorHex: detail.teamBBibColorHex,
        teamBName: detail.teamBName
      )

      Divider()

      VStack(alignment: .leading, spacing: 8) {
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
    .frame(maxWidth: .infinity)
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}

private struct QuarterScoreBreakdown: View {
  var quarters: [GoalTimelineQuarter]
  var teamABibColorHex: String
  var teamAName: String
  var teamBBibColorHex: String
  var teamBName: String

  var body: some View {
    VStack(spacing: 8) {
      Text("Points by quarter")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      VStack(spacing: 6) {
        HStack(spacing: 12) {
          teamName(teamAName, colorHex: teamABibColorHex, alignment: .leading)
          Text("Quarter")
            .frame(width: 64)
          teamName(teamBName, colorHex: teamBBibColorHex, alignment: .trailing)
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
    colorHex: String,
    alignment: Alignment
  ) -> some View {
    HStack(spacing: 5) {
      if alignment == .trailing {
        Spacer(minLength: 0)
      }
      Circle()
        .fill(Color(teamHex: colorHex))
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

private struct GameDetailScore: View {
  var alignment: HorizontalAlignment
  var colorHex: String
  var name: String
  var score: Int

  var body: some View {
    VStack(alignment: alignment, spacing: 8) {
      Capsule()
        .fill(Color(teamHex: colorHex))
        .frame(width: 36, height: 6)
        .accessibilityHidden(true)

      Text(name)
        .font(.headline)
        .lineLimit(3)
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)

      Text("\(score)")
        .font(.system(.largeTitle, design: .rounded, weight: .bold))
        .monospacedDigit()
    }
    .frame(
      maxWidth: .infinity,
      alignment: alignment == .leading ? .leading : .trailing
    )
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
