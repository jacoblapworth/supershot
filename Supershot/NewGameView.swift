import ComposableArchitecture
import SwiftUI

struct NewGameView: View {
  @Bindable var store: StoreOf<NewGameFeature>

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        NewGameTeamsView(store: store)

        if store.leftTeam.team != nil, store.rightTeam.team != nil {
          SetupBibColorsView(
            store: store
          )

          SetupCentrePassView(
            firstCentrePass: $store.firstCentrePass,
            leftTeamName: store.leftTeam.team?.name ?? "Left",
            rightTeamName: store.rightTeam.team?.name ?? "Right"
          )
        }

        SetupTimingView(store: store)
      }
      .padding()
    }
    .navigationTitle("New game")
    .safeAreaInset(edge: .bottom) {
      SetupStartBar(
        canStartGame: store.canStartGame,
        configurationSummary: store.configurationSummary,
        errorMessage: store.teamNameErrorMessage ?? store.errorMessage,
        isSaving: store.isSaving,
        startGameTapped: { store.send(.startGameButtonTapped) }
      )
    }
    .sheet(item: $store.scope(state: \.picker, action: \.picker)) { pickerStore in
      NavigationStack {
        TeamPickerView(store: pickerStore)
        .navigationTitle("Select team")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
      }
      .presentationDetents([.medium, .large])
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
