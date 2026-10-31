import Foundation
import GameCore
import SwiftUI
import UI

package extension Team {
  static let previewRavens = Self(
    id: UUID(),
    name: "North London Ravens",
    colorHex: ColorPalette.blue.hex()
  )
  static let previewSwifts = Self(
    id: UUID(),
    name: "Westminster Swifts",
    colorHex: ColorPalette.red.hex()
  )
  static let previewFoxes = Self(
    id: UUID(),
    name: "Foxes",
    colorHex: "#34C759"
  )
}

package extension [Team] {
  static var previewTeams: Self {
    [
      Team.previewRavens,
      Team.previewSwifts,
      Team.previewFoxes,
    ]
  }
}
