import Database
import SwiftUI
import WidgetSupport

package struct GameRow: View {
  package var game: GameListItem

  package var body: some View {
    GameCardView(game: game.widgetGame)
      .accessibilityValue(game.timingSummary)
      .listRowInsets(.all, 0)
  }

  package init(game: GameListItem) { self.game = game }
}
