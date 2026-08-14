import SwiftUI

struct GamesHomeView: View {
  var deletingGameID: Game.ID?
  var games: [GameListItem]
  var loadingGameID: Game.ID?
  var deleteGameTapped: (Game.ID) -> Void
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
          Button("New Game", action: newGameTapped)
            .buttonStyle(.borderedProminent)
            .fontWeight(.medium)
            .controlSize(.large)
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
          .alignmentGuide(.listRowSeparatorLeading, computeValue: { _ in
            return 0
          })
          .disabled(loadingGameID != nil || deletingGameID != nil)
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", systemImage: "trash", role: .destructive) {
              deleteGameTapped(game.id)
            }
          }
        }
      }
    }
    .navigationTitle("Games")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: newGameTapped) {
          Label("New game", systemImage: "plus")
        }
        .disabled(loadingGameID != nil || deletingGameID != nil)
      }
    }
  }
}

#Preview("Empty games") {
  NavigationStack {
    GamesHomeView(
      deletingGameID: nil,
      games: [],
      loadingGameID: nil,
      deleteGameTapped: { _ in },
      gameTapped: { _ in },
      newGameTapped: {}
    )
  }
}

#Preview("Game history") {
  NavigationStack {
    GamesHomeView(
      deletingGameID: nil,
      games: .previewGames,
      loadingGameID: nil,
      deleteGameTapped: { _ in },
      gameTapped: { _ in },
      newGameTapped: {}
    )
  }
}

#Preview("Loading game") {
  NavigationStack {
    GamesHomeView(
      deletingGameID: nil,
      games: .previewGames,
      loadingGameID: GameListItem.previewInProgress.id,
      deleteGameTapped: { _ in },
      gameTapped: { _ in },
      newGameTapped: {}
    )
  }
}
