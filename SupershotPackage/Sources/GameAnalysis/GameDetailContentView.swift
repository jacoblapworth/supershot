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
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        GameOverviewView(detail: detail) { isAboveViewport in
          isScoreboardAboveViewport = isAboveViewport
        }
        if let location = detail.location {
          GameLocationSection(location: location)
        }
        Section {
          GameAnalysisContentView(
            analysis: detail.analysis,
            selection: selectedAnalysis
          )
            .frame(minHeight: max(viewportHeight - 68, 0), alignment: .top)
          if showsProPromotion {
            ProPromotionCard(exploreProTapped: proPromotionTapped)
          }
        } header: {
          GameAnalysisControl(selection: $selectedAnalysis)
        }
        
        GameMetadataView(detail: detail)
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
    .scrollEdgeEffectStyle(.soft, for: .all)
    .preferredColorScheme(.dark)
    .toolbar {
      ToolbarItem(placement: .principal) {
        if isScoreboardAboveViewport {
          ScoreboardHeaderView(
            left: .init(
              name: detail.teamAName,
              color: detail.teamABibColor,
              score: detail.teamAScore
            ),
            right: .init(
              name: detail.teamBName,
              color: detail.teamBBibColor,
              score: detail.teamBScore
            )
            
          )
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



#Preview("Game detail content") {
  NavigationView {
    GameDetailContentView(
      detail: .previewCompleted,
      showsProPromotion: true,
      proPromotionTapped: {}
    )
  }
}

#Preview("Game without goals") {
  GameDetailContentView(
    detail: .previewNoGoals,
    showsProPromotion: false,
    proPromotionTapped: {}
  )
}
