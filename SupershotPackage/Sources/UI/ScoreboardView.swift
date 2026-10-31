import SwiftUI

/// A scoreboard shared by live and completed games, ordered by court side.
package struct ScoreboardView: View {
  package struct Team {
    package var name: String
    package var color: Color
    package var score: Int
    package var hasCentrePass: Bool

    package init(name: String, color: Color, score: Int, hasCentrePass: Bool = false) {
      self.name = name
      self.color = color
      self.score = score
      self.hasCentrePass = hasCentrePass
    }
  }

  package var left: Team
  package var right: Team

  package init(left: Team, right: Team) {
    self.left = left
    self.right = right
  }

  package var body: some View {
    HStack(spacing: 12) {
      teamScore(left, alignment: .trailing)
      teamScore(right, alignment: .leading)
    }
    .environment(\.layoutDirection, .leftToRight)
  }

  private func teamScore(_ team: Team, alignment: HorizontalAlignment) -> some View {
    TeamScore(
      name: team.name,
      color: team.color,
      score: team.score,
      alignment: alignment,
      hasCentrePass: team.hasCentrePass
    )
  }
}

private struct TeamScore: View {
  var name: String
  var color: Color
  var score: Int
  var alignment: HorizontalAlignment = .leading
  var hasCentrePass: Bool = false

  @Environment(\.isEnabled) var isEnabled
  private var frameAlignment: Alignment {
    switch alignment {
    case .trailing: .trailing
    default: .leading
    }
  }

  var body: some View {
    VStack(alignment: alignment, spacing: 0) {
      HStack {
        if hasCentrePass, alignment == .leading {
          CentrePassIndicator(direction: .leading)
        }
        Text(name)
          .font(.title3)
          .lineLimit(1)
          .truncationMode(.middle)
        if hasCentrePass, alignment == .trailing {
          CentrePassIndicator(direction: .trailing)
        }
      }
      Text("\(score)")
        .font(.system(size: 80, weight: .bold))
        .fontWidth(.compressed)
        .monospacedDigit()
        .teamScoreStyle(color: color)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: frameAlignment)
    .opacity(isEnabled ? 1 : 0.65)
  }
}

private struct CentrePassIndicator: View {
  var direction: HorizontalEdge

  var body: some View {
    Image(systemName: direction == .trailing
      ? "arrow.left.circle.fill"
      : "arrow.right.circle.fill")
      .accessibilityLabel("Current centre pass")
  }
}

#Preview {
  ScoreboardView(
    left: .init(
      name: "Team One",
      color: .red,
      score: 23
    ),
    right: .init(
      name: "Team Two",
      color: .blue,
      score: 20
    )
  )
}
