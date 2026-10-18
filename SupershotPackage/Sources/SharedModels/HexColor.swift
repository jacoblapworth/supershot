import Foundation

/// The canonical opaque sRGB representation used in persisted team colours.
public enum HexColor {
  public nonisolated static func isValid(_ hex: String) -> Bool {
    hex.count == 7 && hex.first == "#"
      && hex.dropFirst().allSatisfy {
        $0.isASCII && $0.isHexDigit
      }
  }
}
