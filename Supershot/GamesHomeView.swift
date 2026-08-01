import SwiftUI

struct GamesHomeView: View {
  var games: [GameListItem]
  var loadingGameID: Game.ID?
  var gameTapped: (GameListItem) -> Void
  var newGameTapped: () -> Void

  var body: some View {
    List {
      if games.isEmpty {
        ContentUnavailableView {
          Label("No games yet", systemImage: "sportscourt")
        } description: {
          Text("Start a game to keep score and build your history.")
        } actions: {
          Button("Start game", action: newGameTapped)
            .buttonStyle(.borderedProminent)
        }
        .listRowBackground(Color.clear)
      } else {
        ForEach(games) { game in
          Button {
            gameTapped(game)
          } label: {
            GameRow(
              game: game,
              isLoading: loadingGameID == game.id
            )
          }
          .buttonStyle(.plain)
          .disabled(loadingGameID != nil)
        }
      }
    }
    .navigationTitle("Games")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: newGameTapped) {
          Label("New game", systemImage: "plus")
        }
        .disabled(loadingGameID != nil)
      }
    }
  }
}

#Preview("Empty games") {
  NavigationStack {
    GamesHomeView(
      games: [],
      loadingGameID: nil,
      gameTapped: { _ in },
      newGameTapped: {}
    )
  }
}

#Preview("Game history") {
  NavigationStack {
    GamesHomeView(
      games: .previewGames,
      loadingGameID: nil,
      gameTapped: { _ in },
      newGameTapped: {}
    )
  }
}

#Preview("Loading game") {
  NavigationStack {
    GamesHomeView(
      games: .previewGames,
      loadingGameID: GameListItem.previewInProgress.id,
      gameTapped: { _ in },
      newGameTapped: {}
    )
  }
}
