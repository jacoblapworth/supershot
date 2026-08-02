import SwiftUI

struct CentrePassControl: View {
  var centrePassTeamID: UUID
  var isShowingOriginalTeamOrder: Bool
  var teamA: ScoringFeature.Team
  var teamB: ScoringFeature.Team
  var centrePassTeamTapped: (UUID) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Centre pass", systemImage: "arrow.left.arrow.right")
        .font(.headline)

      HStack(spacing: 12) {
        if isShowingOriginalTeamOrder {
          centrePassButton(team: teamA)
          centrePassButton(team: teamB)
        } else {
          centrePassButton(team: teamB)
          centrePassButton(team: teamA)
        }
      }

      Text("Tap a team to correct the next centre pass.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
  }

  private func centrePassButton(team: ScoringFeature.Team) -> some View {
    CentrePassButton(
      colorHex: team.bibColorHex,
      isSelected: centrePassTeamID == team.id,
      name: team.name,
      action: { centrePassTeamTapped(team.id) }
    )
  }
}

struct LastCentrePassBanner: View {
  var centrePassTeam: ScoringFeature.Team
  var isTransitioningPeriod: Bool
  var period: Int
  var lastCentrePassNotTakenTapped: () -> Void
  var lastCentrePassTakenTapped: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Quarter \(period) complete", systemImage: "flag.checkered")
        .font(.headline)

      HStack(spacing: 8) {
        Circle()
          .fill(Color(teamHex: centrePassTeam.bibColorHex))
          .frame(width: 12, height: 12)
          .accessibilityHidden(true)
        Text("Did **\(centrePassTeam.name)** take the last centre pass?")
      }

      HStack(spacing: 10) {
        Button("No, not taken", action: lastCentrePassNotTakenTapped)
          .buttonStyle(.bordered)

        Button("Yes, pass taken", action: lastCentrePassTakenTapped)
          .buttonStyle(.borderedProminent)
      }
      .disabled(isTransitioningPeriod)

      if isTransitioningPeriod {
        ProgressView("Saving quarter…")
          .font(.caption)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.accentColor, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }
}

private struct CentrePassButton: View {
  var colorHex: String
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
        isSelected ? Color(teamHex: colorHex).opacity(0.2) : Color.clear,
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(
            isSelected ? Color(teamHex: colorHex) : Color.secondary.opacity(0.4),
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
    centrePassTeamID: ScoringFeature.Team.previewRavens.id,
    isShowingOriginalTeamOrder: true,
    teamA: .previewRavens,
    teamB: .previewSwifts,
    centrePassTeamTapped: { _ in }
  )
  .padding()
}

#Preview("Last centre pass") {
  LastCentrePassBanner(
    centrePassTeam: .previewSwifts,
    isTransitioningPeriod: false,
    period: 2,
    lastCentrePassNotTakenTapped: {},
    lastCentrePassTakenTapped: {}
  )
  .padding()
}

#Preview("Saving quarter") {
  LastCentrePassBanner(
    centrePassTeam: .previewSwifts,
    isTransitioningPeriod: true,
    period: 2,
    lastCentrePassNotTakenTapped: {},
    lastCentrePassTakenTapped: {}
  )
  .padding()
}
