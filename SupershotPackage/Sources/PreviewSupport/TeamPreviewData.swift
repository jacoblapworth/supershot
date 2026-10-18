import Foundation
import GameCore
import SwiftUI
import WidgetSupport

extension Team {
  static package let previewRavens = Self(
    id: UUID(),
    name: "North London Ravens",
    colorHex: ColorPalette.blue.hex()
  )
  static package let previewSwifts = Self(
    id: UUID(),
    name: "Westminster Swifts",
    colorHex: ColorPalette.red.hex()
  )
  static package let previewFoxes = Self(
    id: UUID(),
    name: "Foxes",
    colorHex: "#34C759"
  )
}

extension Array where Element == Team {
  static package var previewTeams: Self {
    [
      Team.previewRavens,
      Team.previewSwifts,
      Team.previewFoxes,
    ]
  }
}
