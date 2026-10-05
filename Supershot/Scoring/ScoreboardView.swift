import SwiftUI
import Foundation

struct ScoreboardView: View {
  var teamA: ScoringFeature.Team
  var teamAScore: Int
  var teamB: ScoringFeature.Team
  var teamBScore: Int
  var centrePassTeamID: UUID
  var swapTeamOrder: Bool = false
  
  var body: some View {
    HStack(spacing: 12) {
      Group {
        TeamScore(
          name: teamA.name,
          color: teamA.bibColor,
          score: teamAScore,
          alignment: swapTeamOrder ? .leading : .trailing,
          hasCentrePass: teamA.id == centrePassTeamID
        )
        TeamScore(
          name: teamB.name,
          color: teamB.bibColor,
          score: teamBScore,
          alignment: swapTeamOrder ? .trailing : .leading,
          hasCentrePass: teamB.id == centrePassTeamID
        )
      }
      .reversed(swapTeamOrder)
    }
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
        .font(.system(size: 64, weight: .bold))
        .fontWidth(.compressed)
        .monospacedDigit()
        .foregroundStyle(color)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: frameAlignment)
    .background(
      Color.white,
      in: RoundedRectangle(cornerRadius: 12)
    )
    .opacity(isEnabled ? 1 : 0.65)
    
  }
}

private struct CentrePassIndicator: View {
  var direction: HorizontalEdge
  
  var body: some View {
    Image(
      systemName: direction == .leading
      ? "arrow.left.circle.fill"
      : "arrow.right.circle.fill"
    )
    .accessibilityLabel("Current centre pass")
  }
}

#Preview("Scoreboard – odd quarters") {
  ScoreboardView(
    teamA: .previewRavens,
    teamAScore: 18,
    teamB: .previewSwifts,
    teamBScore: 16,
    centrePassTeamID: ScoringFeature.Team.previewRavens.id
  )
  .padding()
}

#Preview("Scoreboard – even quarters") {
  ScoreboardView(
    teamA: .previewRavens,
    teamAScore: 18,
    teamB: .previewSwifts,
    teamBScore: 16,
    centrePassTeamID: ScoringFeature.Team.previewRavens.id,
    swapTeamOrder: true
  )
  .padding()
}

#Preview("Scoreboard disabled") {
  ScoreboardView(
    teamA: .previewRavens,
    teamAScore: 18,
    teamB: .previewSwifts,
    teamBScore: 16,
    centrePassTeamID: ScoringFeature.Team.previewRavens.id
  )
  .disabled(true)
  .padding()
}
