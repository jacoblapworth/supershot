import SwiftUI

struct CentrePassControl: View {
  var courtLayout: ScoringFeature.CourtLayout
  var centrePassTeamTapped: (UUID) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Centre pass", systemImage: "arrow.left.arrow.right")
        .font(.headline)

      HStack(spacing: 12) {
        centrePassButton(courtTeam: courtLayout.left)
        centrePassButton(courtTeam: courtLayout.right)
      }
      .environment(\.layoutDirection, .leftToRight)

      Text("Tap a team to correct the next centre pass.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .background(.thinMaterial, in: .containerRelative)
  }

  private func centrePassButton(courtTeam: ScoringFeature.CourtTeam) -> some View {
    CentrePassButton(
      color: courtTeam.team.bibColor,
      isSelected: courtTeam.hasCentrePass,
      name: courtTeam.team.name,
      action: { centrePassTeamTapped(courtTeam.id) }
    )
  }
}

private struct CentrePassButton: View {
  var color: Color
  var isSelected: Bool
  var name: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        Text(name)
          .lineLimit(2)
          .multilineTextAlignment(.center)
      }
      .font(.subheadline.weight(.semibold))
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.horizontal, 8)
      .foregroundStyle(Color.primary)
      .background(
        isSelected ? color.opacity(0.2) : Color.clear,
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(
            isSelected ? color : Color.secondary.opacity(0.4),
            lineWidth: isSelected ? 2 : 1
          )
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(name) centre pass")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

#Preview("Centre pass") {
  CentrePassControl(
    courtLayout: ScoringFeature.State.previewQuarter.courtLayout,
    centrePassTeamTapped: { _ in }
  )
  .padding()
}

