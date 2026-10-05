import SwiftUI

nonisolated enum ColorPalette {
  struct Option: Identifiable, Sendable {
    var id: String { name }
    let color: Color
    let name: String
  }

  static let blue = Color(.sRGB, red: 0, green: 122.0 / 255, blue: 1)
  static let red = Color(.sRGB, red: 1, green: 59.0 / 255, blue: 48.0 / 255)
  static let green = Color(.sRGB, red: 52.0 / 255, green: 199.0 / 255, blue: 89.0 / 255)
  static let orange = Color(.sRGB, red: 1, green: 149.0 / 255, blue: 0)
  static let purple = Color(.sRGB, red: 175.0 / 255, green: 82.0 / 255, blue: 222.0 / 255)
  static let pink = Color(.sRGB, red: 1, green: 45.0 / 255, blue: 85.0 / 255)
  static let teal = Color(.sRGB, red: 48.0 / 255, green: 176.0 / 255, blue: 199.0 / 255)
  static let indigo = Color(.sRGB, red: 88.0 / 255, green: 86.0 / 255, blue: 214.0 / 255)

  static let options = [
    Option(color: blue, name: "Blue"),
    Option(color: red, name: "Red"),
    Option(color: green, name: "Green"),
    Option(color: orange, name: "Orange"),
    Option(color: purple, name: "Purple"),
    Option(color: pink, name: "Pink"),
    Option(color: teal, name: "Teal"),
    Option(color: indigo, name: "Indigo"),
  ]
}
