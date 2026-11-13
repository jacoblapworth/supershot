import AppUI
import Database
import GameCore
import LocationClient
import PaywallFeature
import PreviewSupport
import SharedModels
import SwiftUI
import UI

package struct GameOverviewView: View {
  package var detail: CompletedGameDetail
  var scoreboardVisibilityChanged: (Bool) -> Void
  
  var scoreboard: ScoreboardView {
    ScoreboardView(
      left: .init(name: detail.teamAName, color: detail.teamABibColor, score: detail.teamAScore),
      right: .init(name: detail.teamBName, color: detail.teamBBibColor, score: detail.teamBScore)
    )
  }
  
  package var body: some View {
    VStack(spacing: 20) {
      scoreboard
        .onGeometryChange(for: Bool.self) { geometry in
          geometry.frame(in: .named("gameAnalysisViewport")).maxY <= 0
        } action: { isAboveViewport in
          scoreboardVisibilityChanged(isAboveViewport)
        }
      
    
        ScorePeriodBreakdown(
          periods: detail.goalTimeline.quarters,
          teamABibColor: detail.teamABibColor,
          teamAName: detail.teamAName,
          teamBBibColor: detail.teamBBibColor,
          teamBName: detail.teamBName
        )
    
    }
    .frame(maxWidth: .infinity)
  }
  
  package init(
    detail: CompletedGameDetail,
    scoreboardVisibilityChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.detail = detail
    self.scoreboardVisibilityChanged = scoreboardVisibilityChanged
  }
}

#Preview("Game overview") {
  GameOverviewView(detail: .previewCompleted)
    .padding()
}

#Preview("Drawn game overview") {
  GameOverviewView(detail: .previewDraw)
    .padding()
}
