import GameCore
import SharedModels
import SwiftUI
import WidgetSupport

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
