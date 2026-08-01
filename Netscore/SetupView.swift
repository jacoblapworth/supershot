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
