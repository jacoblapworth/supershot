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
          colorHex: detail.teamAColorHex,
          name: detail.teamAName,
          score: detail.teamAScore
        )

        Text("–")
          .font(.title.bold())
          .foregroundStyle(.secondary)
          .padding(.top, 36)

        GameDetailScore(
          alignment: .trailing,
          colorHex: detail.teamBColorHex,
          name: detail.teamBName,
          score: detail.teamBScore
        )
      }

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
