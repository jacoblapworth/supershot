import SwiftUI

struct GameDetailContentView: View {
  var detail: CompletedGameDetail
  var showsProPromotion: Bool
  var proPromotionTapped: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        GameOverviewView(detail: detail)
        if let location = detail.location {
          GameLocationSection(location: location)
        }
        GameStatisticsView(detail: detail)
        GoalTimelineView(
          teamABibColorHex: detail.teamABibColorHex,
          teamAName: detail.teamAName,
          teamBBibColorHex: detail.teamBBibColorHex,
          teamBName: detail.teamBName,
          timeline: detail.goalTimeline
        )
        if showsProPromotion {
          ProPromotionCard(exploreProTapped: proPromotionTapped)
        }
      }
      .padding()
    }
  }
}

private struct GameLocationSection: View {
  var location: GameLocation

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Location", systemImage: "location.fill")
        .font(.headline)

      GameLocationMap(location: location)

      Label {
        if let pointOfInterestName = location.pointOfInterestName {
          Text(pointOfInterestName)
        } else {
          Text("Game location")
        }
      } icon: {
        Image(systemName: "mappin.and.ellipse")
      }
      .font(.subheadline.weight(.semibold))
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}

#Preview("Game detail content") {
  GameDetailContentView(
    detail: .previewCompleted,
    showsProPromotion: true,
    proPromotionTapped: {}
  )
}

#Preview("Game without goals") {
  GameDetailContentView(
    detail: .previewNoGoals,
    showsProPromotion: false,
    proPromotionTapped: {}
  )
}
