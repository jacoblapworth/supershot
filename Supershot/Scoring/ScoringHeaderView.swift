import SwiftUI

struct ScoringHeaderView: View {
  var courtLayout: ScoringFeature.CourtLayout
  
  var body: some View {
    HStack(spacing: 12) {
      ScoringHeaderTeamScore(courtTeam: courtLayout.left)
      ScoringHeaderTeamScore(courtTeam: courtLayout.right)
    }
    .environment(\.layoutDirection, .leftToRight)
    .accessibilityIdentifier("scoringHeader")
  }
}

private struct ScoringHeaderTeamScore: View {
  var courtTeam: ScoringFeature.CourtTeam
  
  var body: some View {
    Text(courtTeam.score, format: .number)
      .font(.title.bold())
      .fontWidth(.compressed)
      .monospacedDigit()
      .teamScoreStyle(color: courtTeam.team.bibColor)
      .accessibilityLabel("\(courtTeam.team.name), \(courtTeam.score) goals")
  }
}

#Preview("Scoring header") {
  var state = ScoringFeature.State.previewQuarter
  state.teamAScore = 18
  state.teamBScore = 16
  return ScoringHeaderView(courtLayout: state.courtLayout)
}
