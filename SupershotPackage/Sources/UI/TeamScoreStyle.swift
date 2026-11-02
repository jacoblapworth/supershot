import SwiftUI

package extension View {
  /// Uses the team's colour, falling back to white for very dark colours.
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
      .foregroundStyle(luminance < 0.05 ? Color.white : color)
      .shadow(color: .black.opacity(0.2), radius: 5)
  }
}

#Preview("Team score colours") {
  HStack(spacing: 24) {
    Text("24").teamScoreStyle(color: .blue)
    Text("18").teamScoreStyle(color: .yellow)
    Text("12").teamScoreStyle(color: .black)
    Text("9").teamScoreStyle(color: Color(red: 0.05, green: 0.08, blue: 0.15))
  }
  .font(.system(size: 64, weight: .bold))
  .padding()
  .background(.black)
}
