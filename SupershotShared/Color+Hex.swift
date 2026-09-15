import Foundation
import SwiftUI

extension Color {
  nonisolated static func isValidHex(_ hex: String) -> Bool {
    hex.count == 7 && hex.first == "#" && hex.dropFirst().allSatisfy {
      $0.isASCII && $0.isHexDigit
    }
  }

  /// Decodes opaque sRGB database colours. Invalid values fall back to blue.
  nonisolated init(hex: String) {
    let rgb = Self.isValidHex(hex) ? Int(hex.dropFirst(), radix: 16)! : 0x007AFF
    self.init(.sRGB, red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
  }

  /// Encodes an opaque colour for persistence, resolving dynamic colours in the given environment.
  nonisolated func hex(in environment: EnvironmentValues = EnvironmentValues()) -> String {
    let resolved = resolve(in: environment)
    func byte(_ component: Float) -> Int {
      Int((min(max(component, 0), 1) * 255).rounded())
    }
    return String(format: "#%02X%02X%02X", byte(resolved.red), byte(resolved.green), byte(resolved.blue))
  }
}
