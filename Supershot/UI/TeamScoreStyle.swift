import SwiftUI

extension View {
  /// Preserves the team's full colour, with a small shadow to separate it from the background.
  func teamScoreStyle(color: Color) -> some View {
    modifier(TeamScoreStyle(color: color))
  }
}

private struct TeamScoreStyle: ViewModifier {
  var color: Color
  @Environment(\.self) private var environment

  func body(content: Content) -> some View {
    let resolved = color.resolve(in: environment)
    let luminance = resolved.linearRed * 0.2126
      + resolved.linearGreen * 0.7152 + resolved.linearBlue * 0.0722

    content
      .foregroundStyle(color)
      .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
      // A faint light edge also keeps black and navy teams visible on the dark surface.
      .shadow(color: .white.opacity(luminance < 0.12 ? 0.4 : 0), radius: 1)
  }
}
