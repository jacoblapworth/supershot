import ComposableArchitecture
import SwiftUI

struct SetupView: View {
  @Bindable var store: StoreOf<SetupFeature>

  var body: some View {
    Form {
      Section("Teams") {
        TextField("Team A", text: $store.teamAName)
        TextField("Team B", text: $store.teamBName)
      }

      Section("First centre pass") {
        Picker("First centre pass", selection: $store.firstCentrePass) {
          Text(store.trimmedTeamAName.isEmpty ? "Team A" : store.trimmedTeamAName)
            .tag(SetupFeature.TeamSide?.some(.teamA))
          Text(store.trimmedTeamBName.isEmpty ? "Team B" : store.trimmedTeamBName)
            .tag(SetupFeature.TeamSide?.some(.teamB))
        }
        .pickerStyle(.segmented)
      }

      if let errorMessage = store.errorMessage {
        Section {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
        }
      }

      Section {
        Button {
          store.send(.startGameButtonTapped)
        } label: {
          Label("Start game", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
        .disabled(!store.canStartGame)
      }
    }
    .navigationTitle("New game")
  }
}

#Preview {
  SetupView(
    store: Store(initialState: SetupFeature.State()) {
      SetupFeature()
    }
  )
}
