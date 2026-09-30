import ComposableArchitecture
import SwiftUI

struct NewGameTeamsView: View {
  @Bindable var store: StoreOf<NewGameFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Matchup", systemImage: "person.2.fill")
        .font(.headline)

      HStack(spacing: 10) {
        TeamCard(
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
        .buttonStyle(.bordered)
        .disabled(!store.canSwapTeams)
        .accessibilityLabel("Swap left and right teams")

        TeamCard(
          action: { store.send(.selectTeamButtonTapped(.teamB)) },
          team: store.rightTeam.team
        )
      }

    }
    .setupCardStyle()
  }
}



#Preview("Empty matchup") {
  NewGameTeamsView(store: setupPreviewStore())
    .padding()
}

#Preview("Selected matchup") {
  NewGameTeamsView(store: setupPreviewStore(.previewReady))
    .padding()
}

#Preview("Loading matchup") {
  NewGameTeamsView(store: setupPreviewStore(.previewLoading))
    .padding()
}
