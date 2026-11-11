import SwiftUI

package struct ScoreboardHeaderView: View {
  package var left: ScoreboardView.Team
  package var right: ScoreboardView.Team

  package var body: some View {
    HStack(spacing: 12) {
      teamScore(left)
      teamScore(right)
    }
    .environment(\.layoutDirection, .leftToRight)
    .accessibilityIdentifier("scoringHeader")
  }

  package init(left: ScoreboardView.Team, right: ScoreboardView.Team) {
    self.left = left
    self.right = right
  }

  private func teamScore(_ team: ScoreboardView.Team) -> some View {
    Text(team.score, format: .number)
      .font(.title.bold())
      .fontWidth(.compressed)
      .monospacedDigit()
      .teamScoreStyle(color: team.color)
      .accessibilityLabel("\(team.name), \(team.score) goals")
  }
}

#Preview {
  ScoreboardHeaderView(
    left: .init(name: "Team One", color: .red, score: 18),
    right: .init(name: "Team Two", color: .blue, score: 16)
  )
}
