import SwiftUI

struct ScoreboardView: View {
  var isShowingOriginalTeamOrder: Bool
  var teamA: ScoringFeature.Team
  var teamAScore: Int
  var teamB: ScoringFeature.Team
  var teamBScore: Int
  
  var body: some View {
    HStack(spacing: 12) {
      Group {
        TeamScore(name: teamA.name, color: teamA.bibColor, score: teamAScore, alignment: isShowingOriginalTeamOrder ? .leading : .trailing)
        TeamScore(name: teamB.name, color: teamB.bibColor, score: teamBScore, alignment: isShowingOriginalTeamOrder ? .trailing : .leading)
      }
      .reversed(!isShowingOriginalTeamOrder)
    }
  }
}

private struct TeamScore: View {
  var name: String
  var color: Color
  var score: Int
  var alignment: HorizontalAlignment = .leading
  private var frameAlignment: Alignment {
    switch alignment {
    case .trailing: .trailing
    default: .leading
    }
  }
  
  @Environment(\.isEnabled) var isEnabled
  
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
    isDisabled: false,
    isShowingOriginalTeamOrder: true,
    teamA: .previewRavens,
    teamAScore: 18,
    teamB: .previewSwifts,
    teamBScore: 16
  )
  .padding()
}

#Preview("Scoreboard disabled") {
  ScoreboardView(
    isDisabled: true,
    isShowingOriginalTeamOrder: false,
    teamA: .previewRavens,
    teamAScore: 18,
    teamB: .previewSwifts,
    teamBScore: 16
  )
  .padding()
}
