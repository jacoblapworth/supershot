import AppSettings
import ComposableArchitecture
import Database
import GameAnalysis
import GameCore
import GameServices
import LocationClient
import PermissionsFeature
import PreviewSupport
import ScoringFeature
import SharedModels
import Styleguide
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import WidgetSupport

package struct TeamSlotsView: View {
  @Bindable package var store: StoreOf<NewGameFeature>

  package var body: some View {
    HStack(spacing: 10) {
      TeamSlotView(
        action: { store.send(.selectTeamButtonTapped(.teamA)) },
        team: store.leftTeam.team
      )

      Button {
        store.send(.swapTeamsButtonTapped)
      } label: {
        Image(systemName: "arrow.left.arrow.right")
          .font(.headline)
          .frame(width: 34, height: 34)
      }
      .buttonBorderShape(.circle)
      .buttonStyle(.bordered)
      .disabled(!store.canSwapTeams)
      .accessibilityLabel("Swap left and right teams")

      TeamSlotView(
        action: { store.send(.selectTeamButtonTapped(.teamB)) },
        team: store.rightTeam.team
      )
    }
    .disabled(store.isSaving || store.describeGame.isBusy)
  }

  package init(store: StoreOf<NewGameFeature>) {
    self.store = store
  }
}

#Preview("Empty matchup") {
  TeamSlotsView(store: setupPreviewStore())
    .padding()
}

#Preview("Selected matchup") {
  TeamSlotsView(store: setupPreviewStore(.previewReady))
    .padding()
}

#Preview("Loading matchup") {
  TeamSlotsView(store: setupPreviewStore(.previewLoading))
    .padding()
}
