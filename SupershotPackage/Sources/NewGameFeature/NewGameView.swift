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

package struct NewGameView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Bindable package var store: StoreOf<NewGameFeature>
  package var proAccess: SubscriptionEntitlement = .unknown

  package var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        NewGameTeamsView(store: store)

        if store.leftTeam.team != nil, store.rightTeam.team != nil {
          SetupCentrePassView(
            firstCentrePass: $store.firstCentrePass,
            leftTeamName: store.leftTeam.team?.name ?? "Left",
            rightTeamName: store.rightTeam.team?.name ?? "Right"
          )
        }

        SetupTimingSummaryView(timing: store.timing) { store.send(.editTimingButtonTapped) }

          AlarmPermissionCard(
            store: store.scope(state: \.alarms, action: \.alarms),
            proAccess: proAccess
          )
        SetupLocationView(store: store)
      }
      #if os(macOS)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
      #endif
      .padding()
    }
    .navigationTitle("New game")
    .task { store.send(.task) }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { store.send(.sceneBecameActive) }
    }
    .safeAreaInset(edge: .bottom) {
      SetupStartBar(
        canStartGame: store.canStartGame,
        configurationSummary: store.configurationSummary,
        errorMessage: store.teamNameErrorMessage ?? store.errorMessage,
        isSaving: store.isSaving,
        startGameTapped: { store.send(.startGameButtonTapped) }
      )
    }
    .sheet(
      item: $store.scope(state: \.destination, action: \.destination),
      onDismiss: { store.send(.destinationDidDismiss) }
    ) { destinationStore in
      switch destinationStore.case {
      case .teamConfiguration(let configurationStore):
        SetupTeamView(
          store: configurationStore.scope(
            state: \.configuration,
            action: \.configuration
          )
        )

      case .teamPicker(let pickerStore):
        NavigationStack {
          TeamPickerView(
            store: pickerStore.scope(
              state: \.picker,
              action: \.picker
            )
          )
          .navigationTitle("Select team")
          #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
          #endif
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents([.medium, .large])

      case .timingEditor(let timingEditorStore):
        SetupTimingEditorView(store: timingEditorStore)
      }
    }
  }

  package init(store: StoreOf<NewGameFeature>, proAccess: SubscriptionEntitlement = .unknown) {
    self.store = store
    self.proAccess = proAccess
  }
}

#Preview("Empty setup") {
  NavigationStack {
    NewGameView(store: setupPreviewStore())
  }
}

#Preview("Ready to start") {
  NavigationStack {
    NewGameView(store: setupPreviewStore(.previewReady))
  }
}
