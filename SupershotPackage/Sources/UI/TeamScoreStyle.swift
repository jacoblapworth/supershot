import SwiftUI

package extension View {
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
    let luminance =
      resolved.linearRed * 0.2126
        + resolved.linearGreen * 0.7152 + resolved.linearBlue * 0.0722

    content
      .foregroundStyle(color)
      .shadow(color: .black.opacity(0.2), radius: 5)
      // A faint light edge also keeps black and navy teams visible on the dark surface.
      .shadow(color: .white.opacity(luminance < 0.12 ? 0.4 : 0), radius: 1)
  }
}

#Preview("Team score colours") {
  HStack(spacing: 24) {
    Text("24").teamScoreStyle(color: .blue)
    Text("18").teamScoreStyle(color: .yellow)
    Text("12").teamScoreStyle(color: .black)
  }
  .font(.system(size: 64, weight: .bold))
  .padding()
  .background(.black)
}
