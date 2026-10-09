import SwiftUI
import Foundation

struct ScoreboardView: View {
  var courtLayout: ScoringFeature.CourtLayout

  var body: some View {
    HStack(spacing: 12) {
      teamScore(courtLayout.left, alignment: .trailing)
      teamScore(courtLayout.right, alignment: .leading)
    }
    .environment(\.layoutDirection, .leftToRight)
  }

  private func teamScore(
    _ courtTeam: ScoringFeature.CourtTeam,
    alignment: HorizontalAlignment
  ) -> some View {
    TeamScore(
      name: courtTeam.team.name,
      color: courtTeam.team.bibColor,
      score: courtTeam.score,
      alignment: alignment,
      hasCentrePass: courtTeam.hasCentrePass
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
        if hasCentrePass && alignment == .leading {
          CentrePassIndicator(direction: .leading)
        }
        Text(name)
          .font(.title3)
          .lineLimit(1)
        if hasCentrePass && alignment == .trailing {
          CentrePassIndicator(direction: .trailing)
        }
      }
      Text("\(score)")
        .font(.system(size: 80, weight: .bold))
        .fontWidth(.compressed)
        .monospacedDigit()
        .foregroundStyle(color)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: frameAlignment)
    .opacity(isEnabled ? 1 : 0.65)
    
  }
}

private struct CentrePassIndicator: View {
  var direction: HorizontalEdge
  
  var body: some View {
    Image(
      systemName: direction == .trailing
      ? "arrow.left.circle.fill"
      : "arrow.right.circle.fill"
    )
    .accessibilityLabel("Current centre pass")
  }
}

#Preview("Scoreboard – odd quarters") {
  var state = ScoringFeature.State.previewQuarter
  state.currentPhaseIndex = 0
  state.teamAScore = 18
  state.teamBScore = 16
  return ScoreboardView(courtLayout: state.courtLayout)
    .padding()
}

#Preview("Scoreboard – even quarters") {
  var state = ScoringFeature.State.previewQuarter
  state.currentPhaseIndex = 2
  state.teamAScore = 18
  state.teamBScore = 16
  return ScoreboardView(courtLayout: state.courtLayout)
    .padding()
}

#Preview("Scoreboard disabled") {
  var state = ScoringFeature.State.previewQuarter
  state.teamAScore = 18
  state.teamBScore = 16
  return ScoreboardView(courtLayout: state.courtLayout)
    .disabled(true)
    .padding()
}
