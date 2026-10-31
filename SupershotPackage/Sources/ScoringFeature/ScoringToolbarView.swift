import SwiftUI

/// Anchored from the bottom: the primary region can grow only above the goal row.
package struct ScoringToolbarView: View {
  package var state: ScoringToolbarState
  package var onAction: (ScoringControlAction) -> Void

  package var body: some View {
    VStack(spacing: 16) {
      Group {
        switch state.content {
        case .none:
          EmptyView()
        case let .primary(control):
          Button { onAction(control.action) } label: {
            ZStack {
              Label(control.title, systemImage: control.systemImage)
                .opacity(control.availability == .pending ? 0 : 1)
              if control.availability == .pending {
                ProgressView()
              }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.glassProminent)
          .tint(.green)
          .fontWeight(.semibold)
          .disabled(control.availability != .enabled)
          .accessibilityLabel(control.title)
          .accessibilityIdentifier("scoring.primaryAction")
        case let .confirmation(confirmation):
          LastCentrePassBanner(state: confirmation, onAction: onAction)
        }
      }

      ScoringButtonsView(
        courtLayout: state.courtLayout,
        isEnabled: state.canScore,
        onAction: onAction
      )
    }
    .padding()
    .frame(maxWidth: 420)
  }
}

#Preview("Toolbar states") {
  ScrollView {
    VStack(spacing: 24) {
      ForEach(ScoringPreviewScenario.allCases) { scenario in
        VStack {
          Text(scenario.rawValue).font(.caption)
          ScoringToolbarView(state: scenario.state.scoringToolbarState, onAction: { _ in })
        }
      }
    }
  }.preferredColorScheme(.dark)
}

#Preview("Toolbar • large text", traits: .fixedLayout(width: 390, height: 844)) {
  VStack {
    Spacer()
    ScoringToolbarView(
      state: ScoringPreviewScenario.confirmation.state.scoringToolbarState,
      onAction: { _ in }
    )
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}

#Preview("Toolbar • landscape", traits: .fixedLayout(width: 844, height: 390)) {
  VStack {
    Spacer()
    ScoringToolbarView(
      state: ScoringPreviewScenario.confirmation.state.scoringToolbarState,
      onAction: { _ in }
    )
  }.preferredColorScheme(.dark)
}
