import ComposableArchitecture
import SwiftUI

struct NewGameView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Bindable var store: StoreOf<NewGameFeature>
  var proAccess: SubscriptionEntitlement = .unknown

  var body: some View {
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
        
#if os(iOS)
        AlarmPermissionCard(
          store: store.scope(state: \.alarms, action: \.alarms),
          proAccess: proAccess
        )
#endif
        SetupLocationView(store: store)
      }
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
      case let .teamConfiguration(configurationStore):
        SetupTeamView(
          store: configurationStore.scope(
            state: \.configuration,
            action: \.configuration
          )
        )

      case let .teamPicker(pickerStore):
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

      case let .timingEditor(timingEditorStore):
        SetupTimingEditorView(store: timingEditorStore)
      }
    }
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
