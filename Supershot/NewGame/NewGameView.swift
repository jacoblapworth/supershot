import ComposableArchitecture
import SwiftUI

struct NewGameView: View {
  @Bindable var store: StoreOf<NewGameFeature>

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
        
        SetupLocationView(store: store)
      }
      .padding()
    }
    .navigationTitle("New game")
    .task { store.send(.task) }
    .safeAreaInset(edge: .bottom) {
      SetupStartBar(
        canStartGame: store.canStartGame,
        configurationSummary: store.configurationSummary,
        errorMessage: store.teamNameErrorMessage ?? store.errorMessage,
        isSaving: store.isSaving,
        startGameTapped: { store.send(.startGameButtonTapped) }
      )
    }
    .sheet(item: $store.scope(state: \.picker, action: \.picker), onDismiss: { store.send(.pickerDidDismiss) }) { pickerStore in
      NavigationStack {
        TeamPickerView(store: pickerStore)
        .navigationTitle("Select team")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
      }
      .presentationDetents([.medium, .large])
    }
    .sheet(item: $store.scope(state: \.teamConfiguration, action: \.teamConfiguration)) {
      SetupTeamView(store: $0)
    }
    .sheet(item: $store.scope(state: \.timingEditor, action: \.timingEditor)) {
      SetupTimingEditorView(store: $0)
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
