import SwiftUI

package struct ScoringButtonsView: View {
  package var courtLayout: ScoringFeature.CourtLayout
  package var onAction: (ScoringControlAction) -> Void
  @Namespace private var animation
  @Environment(\.isEnabled) private var isEnabled
  
  package var body: some View {
    Grid {
      GridRow {
        goalButton(for: courtLayout.left)
        goalButton(for: courtLayout.right)
      }
      GridRow {
        centrePassIndicator(for: courtLayout.left)
        centrePassIndicator(for: courtLayout.right)
      }
    }
    .environment(\.layoutDirection, .leftToRight)
    .buttonSizing(.flexible)
    .buttonStyle(.glassProminent)
    .animation(.smooth(duration: 0.25), value: courtLayout.left.hasCentrePass)
  }
  
  private func centrePassIndicator(for team: ScoringFeature.CourtTeam) -> some View {
    ZStack {
      Color.clear
      if team.hasCentrePass {
        RoundedRectangle(cornerRadius: 8)
          .fill(isEnabled
                ? AnyShapeStyle(team.team.bibColor)
                : AnyShapeStyle(Material.thin)
          )
          .glassEffect()
          .matchedGeometryEffect(id: "centrePass", in: animation)
      }
    }
    .frame(height: 6)
    .padding(.horizontal, 40)
    .accessibilityHidden(true)
  }
  
  private func goalButton(for team: ScoringFeature.CourtTeam) -> some View {
    Button {
      withAnimation {
        onAction(.goal(team.id))
      }
    } label: {
      Label("Goal", systemImage: "plus")
        .font(.title2.bold())
        .frame(maxWidth: .infinity, minHeight: 80)
    }
    .tint(team.team.bibColor)
    .accessibilityLabel("Goal for \(team.team.name)")
    .accessibilityValue(team.hasCentrePass ? "Centre pass" : "")
    .accessibilityIdentifier("scoring.goal.\(team.id)")
    .labelStyle(.iconOnly)
  }
}

#Preview("Goal buttons") {
  VStack(spacing: 24) {
    ScoringButtonsView(
      courtLayout: ScoringFeature.State.previewQuarter.courtLayout,
      onAction: { _ in }
    )
    ScoringButtonsView(
      courtLayout: ScoringFeature.State.previewQuarter.courtLayout,
      onAction: { _ in }
    )
    .disabled(true)
  }.padding()
}

#Preview("Centre pass indicator") {
  @Previewable @State var state = ScoringPreviewScenario.running.state
  VStack(spacing: 24) {
    ScoringButtonsView(courtLayout: state.courtLayout, onAction: { _ in })
    Button("Change centre pass") {
      state.centrePassTeamID = state.centrePassTeamID == state.teamA.id ? state.teamB.id : state.teamA.id
    }
    Button("Swap sides") {
      state.swapSides.toggle()
    }
  }
  .padding()
}
