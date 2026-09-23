import SwiftUI

struct ScoreboardView: View {
  var teamA: ScoringFeature.Team
  var teamAScore: Int
  var teamB: ScoringFeature.Team
  var teamBScore: Int
  var swapTeamOrder: Bool = false
  
  var body: some View {
    HStack(spacing: 12) {
      Group {
        TeamScore(name: teamA.name, color: teamA.bibColor, score: teamAScore, alignment: swapTeamOrder ? .leading : .trailing)
        TeamScore(name: teamB.name, color: teamB.bibColor, score: teamBScore, alignment: swapTeamOrder ? .trailing : .leading)
      }
      .reversed(!swapTeamOrder)
    }
  }
}

private struct TeamScore: View {
  var name: String
  var color: Color
  var score: Int
  var alignment: HorizontalAlignment = .leading

  @Environment(\.isEnabled) var isEnabled
  private var frameAlignment: Alignment {
    switch alignment {
    case .trailing: .trailing
    default: .leading
    }
  }
  
  
  var body: some View {
    VStack(alignment: alignment, spacing: 0) {
      Text(name)
        .font(.headline)
        .lineLimit(1)
      Text("\(score)")
        .font(.system(size: 64, weight: .bold))
        .fontWidth(.compressed)
        .monospacedDigit()
        .foregroundStyle(color)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: frameAlignment)
    .background(
      color.opacity(0.12),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .opacity(isEnabled ? 1 : 0.65)
    
  }
}

#Preview("Scoreboard") {
  ScoreboardView(
    teamA: .previewRavens,
    teamAScore: 18,
    teamB: .previewSwifts,
    teamBScore: 16,
    swapTeamOrder: true
  )
  .padding()
}

#Preview("Scoreboard disabled") {
  ScoreboardView(
    teamA: .previewRavens,
    teamAScore: 18,
    teamB: .previewSwifts,
    teamBScore: 16
  )
  .disabled(true)
  .padding()
}
