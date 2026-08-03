import ComposableArchitecture
import SwiftUI

struct NewGameView: View {
  @Bindable var store: StoreOf<NewGameFeature>

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        NewGameTeamsView(store: store)

        if store.leftTeam.isLocked, store.rightTeam.isLocked {
          SetupBibColorsView(
            leftStore: store.scope(state: \.leftTeam, action: \.leftTeam),
            rightStore: store.scope(state: \.rightTeam, action: \.rightTeam)
          )

          SetupCentrePassView(
            firstCentrePass: $store.firstCentrePass,
            leftTeamName: store.leftTeam.selectedDraft?.trimmedName ?? "Left",
            rightTeamName: store.rightTeam.selectedDraft?.trimmedName ?? "Right"
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
    .confirmationDialog(
      $store.scope(state: \.confirmationDialog, action: \.confirmationDialog)
    )
    .sheet(isPresented: $store.isPresentingTeamPicker) {
      NavigationStack {
        Group {
          if store.leftTeam.mode.isInteracting {
            TeamSlotPanel(
              store: store.scope(state: \.leftTeam, action: \.leftTeam),
              teams: store.availableTeams,
              unavailableTeamID: store.rightTeam.selection?.existingID
            )
          } else if store.rightTeam.mode.isInteracting {
            TeamSlotPanel(
              store: store.scope(state: \.rightTeam, action: \.rightTeam),
              teams: store.availableTeams,
              unavailableTeamID: store.leftTeam.selection?.existingID
            )
          }
        }
        .padding()
        .navigationTitle("Select team")
        .navigationBarTitleDisplayMode(.inline)
      }
      .presentationDetents([.medium, .large])
    }
    .task {
      store.send(.task)
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
