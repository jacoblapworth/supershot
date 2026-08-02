import SwiftUI

struct ScoringScoreboardView: View {
  var isDisabled: Bool
  var isShowingOriginalTeamOrder: Bool
  var teamA: ScoringFeature.Team
  var teamAScore: Int
  var teamB: ScoringFeature.Team
  var teamBScore: Int
  var goalTapped: (UUID) -> Void

  var body: some View {
    HStack(spacing: 12) {
      if isShowingOriginalTeamOrder {
        scoreButton(team: teamA, score: teamAScore)
        scoreButton(team: teamB, score: teamBScore)
      } else {
        scoreButton(team: teamB, score: teamBScore)
        scoreButton(team: teamA, score: teamAScore)
      }
    }
  }

  private func scoreButton(
    team: ScoringFeature.Team,
    score: Int
  ) -> some View {
    ScoreButton(
      colorHex: team.bibColorHex,
      isDisabled: isDisabled,
      name: team.name,
      score: score,
      action: { goalTapped(team.id) }
    )
  }
}

private struct ScoreButton: View {
  var colorHex: String
  var isDisabled: Bool
  var name: String
  var score: Int
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 10) {
        Text(name)
          .font(.headline)
          .lineLimit(2)
          .multilineTextAlignment(.center)
          .frame(minHeight: 44)

        Text("\(score)")
          .font(.system(size: 64, weight: .bold, design: .rounded))
          .monospacedDigit()

        Label("Goal", systemImage: "plus.circle.fill")
          .font(.subheadline.weight(.semibold))
      }
      .frame(maxWidth: .infinity, minHeight: 180)
      .background(
        Color(teamHex: colorHex).opacity(0.12),
        in: RoundedRectangle(cornerRadius: 12)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color(teamHex: colorHex), lineWidth: 2)
      }
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.65 : 1)
  }
}

#Preview("Scoreboard") {
  ScoringScoreboardView(
    isDisabled: false,
    isShowingOriginalTeamOrder: true,
    teamA: .previewRavens,
    teamAScore: 18,
    teamB: .previewSwifts,
    teamBScore: 16,
    goalTapped: { _ in }
  )
  .padding()
}

#Preview("Scoreboard disabled") {
  ScoringScoreboardView(
    isDisabled: true,
    isShowingOriginalTeamOrder: false,
    teamA: .previewRavens,
    teamAScore: 18,
    teamB: .previewSwifts,
    teamBScore: 16,
    goalTapped: { _ in }
  )
  .padding()
}
