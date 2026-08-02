import SwiftUI

struct GameDetailContentView: View {
  var detail: CompletedGameDetail

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        GameOverviewView(detail: detail)
        GameStatisticsView(detail: detail)
        GoalTimelineView(
          teamABibColorHex: detail.teamABibColorHex,
          teamAName: detail.teamAName,
          teamBBibColorHex: detail.teamBBibColorHex,
          teamBName: detail.teamBName,
          timeline: detail.goalTimeline
        )
      }
      .padding()
    }
  }
}

#Preview("Game detail content") {
  GameDetailContentView(detail: .previewCompleted)
}

#Preview("Game without goals") {
  GameDetailContentView(detail: .previewNoGoals)
}
