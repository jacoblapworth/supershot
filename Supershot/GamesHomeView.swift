import SwiftUI

struct GamesHomeView: View {
  var games: [GameListItem]
  var isResumingGame: Bool
  var showsProPromotion: Bool
  var deleteGameTapped: (Game.ID) -> Void
  var gameTapped: (GameListItem) -> Void
  var newGameTapped: () -> Void
  var proPromotionTapped: () -> Void
  
  var body: some View {
    List {
      if showsProPromotion {
        Section {
          ProPromotionCard(exploreProTapped: proPromotionTapped)
            .listRowBackground(Color.clear)
            .listRowInsets(.all, 0)
        }
      }
      
      Section {
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
                game: game
              )
            }
            
            .buttonStyle(.plain)
            .alignmentGuide(.listRowSeparatorLeading, computeValue: { _ in
              return 0
            })
            .disabled(isResumingGame)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
              Button("Delete", systemImage: "trash", role: .destructive) {
                deleteGameTapped(game.id)
              }
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
        .disabled(isResumingGame)
      }
    }
  }
}

#Preview("Empty games") {
  NavigationStack {
    GamesHomeView(
      games: [],
      isResumingGame: false,
      showsProPromotion: true,
      deleteGameTapped: { _ in },
      gameTapped: { _ in },
      newGameTapped: {},
      proPromotionTapped: {}
    )
  }
}

#Preview("Game history") {
  NavigationStack {
    GamesHomeView(
      games: .previewGames,
      isResumingGame: false,
      showsProPromotion: true,
      deleteGameTapped: { _ in },
      gameTapped: { _ in },
      newGameTapped: {},
      proPromotionTapped: {}
    )
  }
}

#Preview("Loading game") {
  NavigationStack {
    GamesHomeView(
      games: .previewGames,
      isResumingGame: true,
      showsProPromotion: false,
      deleteGameTapped: { _ in },
      gameTapped: { _ in },
      newGameTapped: {},
      proPromotionTapped: {}
    )
  }
}
