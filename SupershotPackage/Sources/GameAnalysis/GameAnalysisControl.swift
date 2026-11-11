import AppUI
import Database
import GameCore
import LocationClient
import PaywallFeature
import PreviewSupport
import SharedModels
import SwiftUI
import UI

package enum GameAnalysisTab: String, CaseIterable, Identifiable {
  case stats = "Stats"
  case playByPlay = "Play-by-play"

  package var id: Self {
    self
  }
}

package struct GameAnalysisControl: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isPinned = false
  @Namespace private var selectionAnimation
  @Binding package var selection: GameAnalysisTab

  package var body: some View {
    HStack(spacing: 4) {
      ForEach(GameAnalysisTab.allCases) { tab in
        Button {
          withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            selection = tab
          }
        } label: {
          Text(tab.rawValue)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selection == tab ? .primary : .secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background {
              if selection == tab {
                RoundedRectangle(cornerRadius: 12)
                  .fill(.quaternary)
                  .matchedGeometryEffect(id: "selection", in: selectionAnimation)
              }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
        .accessibilityIdentifier("gameAnalysis.\(tab == .playByPlay ? "playByPlay" : "stats")")
      }
    }
    .padding(4)
    .background {
      if !isPinned {
        RoundedRectangle(cornerRadius: 16)
          .fill(.regularMaterial)
      }
    }
    .padding(.vertical, 8)
    .background {
      if isPinned {
        Rectangle()
          .fill(.bar)
          .padding(.horizontal, -16)
      }
    }
    .onGeometryChange(for: Bool.self) { geometry in
      geometry.frame(in: .named("gameAnalysisViewport")).minY <= 0.5
    } action: {
      isPinned = $0
    }
    #if os(iOS)
    .toolbarBackground(.bar, for: .navigationBar)
    .toolbarBackground(isPinned ? .visible : .automatic, for: .navigationBar)
    #endif
  }

  package init(selection: Binding<GameAnalysisTab>) {
    _selection = selection
  }
}

package struct GameAnalysisContentView: View {
  package var analysis: GameAnalysis
  package var selection: GameAnalysisTab
  package var teamAOnLeft = true
  package var deleteGoal: ((Goal.ID) -> Void)?

  package var body: some View {
    switch selection {
    case .playByPlay:
      GoalTimelineView(
        teamABibColor: analysis.teamABibColor,
        teamAName: analysis.teamAName,
        teamBBibColor: analysis.teamBBibColor,
        teamBName: analysis.teamBName,
        timeline: analysis.goalTimeline,
        teamAOnLeft: teamAOnLeft,
        deleteGoal: deleteGoal
      )
    case .stats:
      GameStatisticsView(detail: analysis)
    }
  }

  package init(
    analysis: GameAnalysis,
    selection: GameAnalysisTab,
    teamAOnLeft: Bool = true,
    deleteGoal: ((Goal.ID) -> Void)? = nil
  ) {
    self.analysis = analysis
    self.selection = selection
    self.teamAOnLeft = teamAOnLeft
    self.deleteGoal = deleteGoal
  }
}

#Preview {
  @Previewable @State var selection = GameAnalysisTab.playByPlay
  GameAnalysisControl(selection: $selection)
    .padding()
    .preferredColorScheme(.dark)
}
