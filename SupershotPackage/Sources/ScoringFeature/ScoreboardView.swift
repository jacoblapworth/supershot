import AppUI
import PreviewSupport
import SwiftUI
import UI

package extension ScoreboardView {
  init(courtLayout: ScoringFeature.CourtLayout) {
    self.init(
      left: .init(
        name: courtLayout.left.team.name,
        color: courtLayout.left.team.bibColor,
        score: courtLayout.left.score,
        hasCentrePass: courtLayout.left.hasCentrePass
      ),
      right: .init(
        name: courtLayout.right.team.name,
        color: courtLayout.right.team.bibColor,
        score: courtLayout.right.score,
        hasCentrePass: courtLayout.right.hasCentrePass
      )
    )
  }
}

#Preview("Scoreboard – odd quarters") {
  var state = ScoringFeature.State.previewQuarter
  state.currentPhaseIndex = 0
  state.teamAScore = 18
  state.teamBScore = 16
  return ScoreboardView(courtLayout: state.courtLayout)
    .padding()
}

#Preview("Scoreboard – even quarters") {
  var state = ScoringFeature.State.previewQuarter
  state.currentPhaseIndex = 2
  state.teamAScore = 18
  state.teamBScore = 16
  return ScoreboardView(courtLayout: state.courtLayout)
    .padding()
}

#Preview("Scoreboard disabled") {
  var state = ScoringFeature.State.previewQuarter
  state.teamAScore = 18
  state.teamBScore = 16
  return ScoreboardView(courtLayout: state.courtLayout)
    .disabled(true)
    .padding()
}
