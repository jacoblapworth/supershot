import GameCore
import SharedModels
import SwiftUI
import WidgetSupport

nonisolated extension Team {
  public var color: Color { Color(hex: colorHex) }
}

nonisolated extension Game {
  public var teamABibColor: Color { Color(hex: teamABibColorHex) }
  public var teamBBibColor: Color { Color(hex: teamBBibColorHex) }
}
