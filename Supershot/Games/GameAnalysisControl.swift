import SwiftUI

enum GameAnalysisTab: String, CaseIterable, Identifiable {
  case playByPlay = "Play-by-play"
  case stats = "Stats"

  var id: Self { self }
}

struct GameAnalysisControl: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionAnimation
  @Binding var selection: GameAnalysisTab

  var body: some View {
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
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .padding(.vertical, 8)
  }
}

struct GameAnalysisContentView: View {
  var analysis: GameAnalysis
  var selection: GameAnalysisTab

  var body: some View {
    switch selection {
    case .playByPlay:
      GoalTimelineView(
        teamABibColor: analysis.teamABibColor,
        teamAName: analysis.teamAName,
        teamBBibColor: analysis.teamBBibColor,
        teamBName: analysis.teamBName,
        timeline: analysis.goalTimeline
      )
    case .stats:
      GameStatisticsView(detail: analysis)
    }
  }
}

#Preview {
  @Previewable @State var selection = GameAnalysisTab.playByPlay
  GameAnalysisControl(selection: $selection)
    .padding()
    .preferredColorScheme(.dark)
}
