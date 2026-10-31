import AlarmClient
import AppSettings
import AppUI
import Database
import GameAnalysis
import GameCore
import GameServices
import PermissionsFeature
import PreviewSupport
import SharedModels
import SoundEffectsClient
import SubscriptionClient
import SwiftUI
import UI

package struct CentrePassControl: View {
  package var courtLayout: ScoringFeature.CourtLayout
  package var centrePassTeamTapped: (UUID) -> Void

  package var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Centre pass", systemImage: "arrow.left.arrow.right")
        .font(.headline)

      HStack(spacing: 12) {
        centrePassButton(courtTeam: courtLayout.left)
        centrePassButton(courtTeam: courtLayout.right)
      }
      .environment(\.layoutDirection, .leftToRight)

      Text("Tap a team to correct the next centre pass.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .background(.thinMaterial, in: .containerRelative)
  }

  private func centrePassButton(courtTeam: ScoringFeature.CourtTeam) -> some View {
    CentrePassButton(
      color: courtTeam.team.bibColor,
      isSelected: courtTeam.hasCentrePass,
      name: courtTeam.team.name,
      action: { centrePassTeamTapped(courtTeam.id) }
    )
  }

  package init(courtLayout: ScoringFeature.CourtLayout, centrePassTeamTapped: @escaping (UUID) -> Void) {
    self.courtLayout = courtLayout
    self.centrePassTeamTapped = centrePassTeamTapped
  }
}

#Preview("Centre pass") {
  CentrePassControl(
    courtLayout: ScoringFeature.State.previewQuarter.courtLayout,
    centrePassTeamTapped: { _ in }
  )
  .padding()
}
