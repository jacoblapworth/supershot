import AlarmClient
import AppSettings
import Database
import GameAnalysis
import GameCore
import GameServices
import PermissionsFeature
import PreviewSupport
import SharedModels
import SoundEffectsClient
import Styleguide
import SubscriptionClient
import SwiftUI
import WidgetSupport

package struct ScoringHeaderView: View {
  package var courtLayout: ScoringFeature.CourtLayout

  package var body: some View {
    HStack(spacing: 12) {
      ScoringHeaderTeamScore(courtTeam: courtLayout.left)
      ScoringHeaderTeamScore(courtTeam: courtLayout.right)
    }
    .environment(\.layoutDirection, .leftToRight)
    .accessibilityIdentifier("scoringHeader")
  }

  package init(courtLayout: ScoringFeature.CourtLayout) {
    self.courtLayout = courtLayout
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
