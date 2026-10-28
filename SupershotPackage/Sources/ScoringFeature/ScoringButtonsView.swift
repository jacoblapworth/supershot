import SwiftUI

package struct ScoringButtonsView: View {
  package var courtLayout: ScoringFeature.CourtLayout
  package var isEnabled: Bool
  package var onAction: (ScoringControlAction) -> Void

  package var body: some View {
    HStack(spacing: 16) {
      goalButton(for: courtLayout.left)
      goalButton(for: courtLayout.right)
    }
    .environment(\.layoutDirection, .leftToRight)
    .buttonSizing(.flexible)
    .buttonStyle(.glassProminent)
    .disabled(!isEnabled)
  }

  private func goalButton(for team: ScoringFeature.CourtTeam) -> some View {
    Button { onAction(.goal(team.id)) } label: {
      Label("Goal", systemImage: "plus")
        .font(.title2.bold())
        .frame(maxWidth: .infinity, minHeight: 80)
    }
    .tint(team.team.bibColor)
    .accessibilityLabel("Goal for \(team.team.name)")
    .accessibilityIdentifier("scoring.goal.\(team.id)")
    .labelStyle(.iconOnly)
  }
}

#Preview("Goal buttons") {
  VStack(spacing: 24) {
    ScoringButtonsView(courtLayout: ScoringFeature.State.previewQuarter.courtLayout,
                       isEnabled: true, onAction: { _ in })
    ScoringButtonsView(courtLayout: ScoringFeature.State.previewQuarter.courtLayout,
                       isEnabled: false, onAction: { _ in })
  }.padding()
}
