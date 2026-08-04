import SwiftUI

struct GameRow: View {
  var game: GameListItem
  var isLoading: Bool

  var body: some View {
    VStack(spacing: 14) {


      HStack(alignment: .center, spacing: 12) {
        TeamScore(
          alignment: .leading,
          colorHex: game.teamABibColorHex,
          name: game.teamAName,
          score: game.teamAScore,
          scoreColor: scoreColor(for: game.teamAScore, opponentScore: game.teamBScore)
        )

//        Text("–")
//          .font(.title2.bold())
//          .foregroundStyle(.secondary)

        TeamScore(
          alignment: .trailing,
          colorHex: game.teamBBibColorHex,
          name: game.teamBName,
          score: game.teamBScore,
          scoreColor: scoreColor(for: game.teamBScore, opponentScore: game.teamAScore)
        )
      }
      
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
    }
    .padding(.vertical, 8)
//    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private func scoreColor(for score: Int, opponentScore: Int) -> Color {
    guard game.isCompleted, score < opponentScore else { return .primary }
    return .secondary
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
  var scoreColor: Color

  var body: some View {
    VStack(alignment: alignment, spacing: 4) {
      Circle()
        .fill(Color(teamHex: colorHex))
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)

      Text(name)
        .font(.default)
        .lineLimit(3)
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        .foregroundStyle(.secondary)

      Text("\(score)")
        .font(.system(.largeTitle, design: .rounded, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(scoreColor)
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
