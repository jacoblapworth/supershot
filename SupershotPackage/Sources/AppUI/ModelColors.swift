import GameCore
import SwiftUI
import UI

public nonisolated extension Team {
  var color: Color {
    Color(hex: colorHex)
  }
}

public nonisolated extension Game {
  var teamABibColor: Color {
    Color(hex: teamABibColorHex)
  }

  var teamBBibColor: Color {
    Color(hex: teamBBibColorHex)
  }
}
