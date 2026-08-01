import SwiftUI

struct GameRow: View {
  var game: GameListItem
  var isLoading: Bool

  var body: some View {
    VStack(spacing: 14) {
      HStack(spacing: 8) {
        Text(game.startedAt.formatted(date: .abbreviated, time: .shortened))
          .foregroundStyle(.secondary)

        Spacer(minLength: 8)

        if isLoading {
          ProgressView()
            .controlSize(.small)
        } else {
          Label(
            game.isCompleted ? "Final" : "In progress",
            systemImage: game.isCompleted ? "checkmark.circle.fill" : "clock.fill"
          )
          .foregroundStyle(game.isCompleted ? Color.secondary : Color.accentColor)
        }
      }
      .font(.caption.weight(.semibold))

      HStack(alignment: .center, spacing: 12) {
        TeamScore(
          alignment: .leading,
          colorHex: game.teamAColorHex,
          name: game.teamAName,
          score: game.teamAScore
        )

        Text("–")
          .font(.title2.bold())
          .foregroundStyle(.secondary)

        TeamScore(
          alignment: .trailing,
          colorHex: game.teamBColorHex,
          name: game.teamBName,
          score: game.teamBScore
        )
      }

      Text(game.timingSummary)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 8)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var accessibilityText: String {
    let date = game.startedAt.formatted(date: .abbreviated, time: .shortened)
    let status = game.isCompleted ? "Final" : "In progress"
    return "\(date), \(game.teamAName) \(game.teamAScore), "
      + "\(game.teamBName) \(game.teamBScore), \(status), \(game.timingSummary)"
  }
}

private struct TeamScore: View {
  var alignment: HorizontalAlignment
  var colorHex: String
  var name: String
  var score: Int

  var body: some View {
    VStack(alignment: alignment, spacing: 4) {
      Circle()
        .fill(Color(teamHex: colorHex))
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)

      Text(name)
        .font(.headline)
        .lineLimit(3)
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)

      Text("\(score)")
        .font(.system(.title, design: .rounded, weight: .bold))
        .monospacedDigit()
    }
    .frame(
      maxWidth: .infinity,
      alignment: alignment == .leading ? .leading : .trailing
    )
  }
}

#Preview("In-progress game") {
  GameRow(game: .previewInProgress, isLoading: false)
    .padding()
}

#Preview("Completed game row") {
  GameRow(game: .previewCompleted, isLoading: false)
    .padding()
}

#Preview("Loading game row") {
  GameRow(game: .previewInProgress, isLoading: true)
    .padding()
}
