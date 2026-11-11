import AppUI
import Database
import GameCore
import LocationClient
import PaywallFeature
import PreviewSupport
import SharedModels
import SwiftUI
import UI

package struct GameDetailContentView: View {
  @State private var selectedAnalysis = GameAnalysisTab.stats
  @State private var viewportHeight: CGFloat = 0
  @State private var isScoreboardAboveViewport = false
  package var detail: CompletedGameDetail
  package var showsProPromotion: Bool
  package var proPromotionTapped: () -> Void

  package var body: some View {
    let overview = GameOverviewView(detail: detail) { isAboveViewport in
      isScoreboardAboveViewport = isAboveViewport
    }

    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
        overview
          .padding(.top)
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
      #if os(macOS)
      .frame(maxWidth: 960)
      .frame(maxWidth: .infinity)
      #endif
      .padding(.horizontal)
      .padding(.bottom)
    }
    .coordinateSpace(name: "gameAnalysisViewport")
    .onGeometryChange(for: CGFloat.self) {
      $0.size.height
    } action: {
      viewportHeight = $0
    }
    .background {
      TeamColorBackground(
        leftColor: detail.teamABibColor,
        rightColor: detail.teamBBibColor
      )
      .ignoresSafeArea()
    }
    .preferredColorScheme(.dark)
    .toolbar {
      ToolbarItem(placement: .principal) {
        if isScoreboardAboveViewport {
          let scoreboard = overview.scoreboard
          ScoreboardHeaderView(left: scoreboard.left, right: scoreboard.right)
        }
      }
    }
  }

  package init(detail: CompletedGameDetail, showsProPromotion: Bool, proPromotionTapped: @escaping () -> Void) {
    self.detail = detail
    self.showsProPromotion = showsProPromotion
    self.proPromotionTapped = proPromotionTapped
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
