import Foundation
import SwiftUI

nonisolated enum TeamColorPalette {
  struct Option: Equatable, Hashable, Identifiable, Sendable {
    var id: String { hex }
    let hex: String
    let name: String
  }

  static let blue = "#007AFF"
  static let red = "#FF3B30"

  static let options = [
    Option(hex: blue, name: "Blue"),
    Option(hex: red, name: "Red"),
    Option(hex: "#34C759", name: "Green"),
    Option(hex: "#FF9500", name: "Orange"),
    Option(hex: "#AF52DE", name: "Purple"),
    Option(hex: "#FF2D55", name: "Pink"),
    Option(hex: "#30B0C7", name: "Teal"),
    Option(hex: "#5856D6", name: "Indigo"),
  ]

  static func isValid(_ hex: String) -> Bool {
    guard hex.count == 7, hex.first == "#" else { return false }
    return hex.dropFirst().allSatisfy(\.isHexDigit)
  }
}

extension Color {
  init(teamHex: String) {
    let value = TeamColorPalette.isValid(teamHex)
      ? String(teamHex.dropFirst())
      : String(TeamColorPalette.blue.dropFirst())
    let rgb = Int(value, radix: 16) ?? 0x007AFF
    self.init(
      .sRGB,
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255,
      opacity: 1
    )
  }
}
