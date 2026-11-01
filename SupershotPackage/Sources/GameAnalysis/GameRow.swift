import Database
import SwiftUI
import UI

package struct GameRow: View {
  package var game: GameListItem

  package var body: some View {
    GameCardView(game: game.widgetGame, teamALogoData: game.teamALogoData, teamBLogoData: game.teamBLogoData)
      .accessibilityValue(game.timingSummary)
      .listRowInsets(.all, 0)
  }

  package init(game: GameListItem) {
    self.game = game
  }
}
