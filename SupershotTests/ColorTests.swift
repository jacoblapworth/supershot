import SwiftUI
import Testing

@testable import Supershot

extension SupershotTestSuite {
  struct ColorTests {
    @Test(arguments: ["#000000", "#FFFFFF", "#007AFF", "#34c759", "#FF2D55"])
    func databaseColorRoundTrips(hex: String) {
      #expect(Color(hex: hex).hex() == hex.uppercased())
    }

    @Test(arguments: ["", "007AFF", "#12345G", "#１２３４５６", "#123", "#12345678"])
    func invalidDatabaseColorsFallBackToBlue(hex: String) {
      #expect(!Color.isValidHex(hex))
      #expect(Color(hex: hex).hex() == "#007AFF")
    }

    @Test
    func storedPaletteColorsKeepTheirSelectionIdentity() {
      for option in ColorPalette.options {
        #expect(Color(hex: option.color.hex()) == option.color)
      }
    }

    @Test
    func extendedComponentsAreClampedForStorage() {
      #expect(Color(.sRGB, red: 1.2, green: -0.1, blue: 0.5).hex() == "#FF0080")
    }
  }
}
