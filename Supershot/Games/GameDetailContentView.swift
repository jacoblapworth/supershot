import SwiftUI

struct GameDetailContentView: View {
  @State private var selectedAnalysis = GameAnalysisTab.playByPlay
  @State private var viewportHeight: CGFloat = 0
  var detail: CompletedGameDetail
  var showsProPromotion: Bool
  var proPromotionTapped: () -> Void

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 28, pinnedViews: [.sectionHeaders]) {
        GameOverviewView(detail: detail)
        if let location = detail.location {
          GameLocationSection(location: location)
        }
        Section {
          GameAnalysisContentView(analysis: detail.analysis, selection: selectedAnalysis)
            .frame(minHeight: max(viewportHeight - 68, 0), alignment: .top)
          if showsProPromotion {
            ProPromotionCard(exploreProTapped: proPromotionTapped)
          }
        } header: {
          GameAnalysisControl(selection: $selectedAnalysis)
        }
      }
      .padding()
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
    .background {
      TeamColorBackground(
        leftColor: detail.teamABibColor,
        rightColor: detail.teamBBibColor
      )
      .ignoresSafeArea()
    }
    .preferredColorScheme(.dark)
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
