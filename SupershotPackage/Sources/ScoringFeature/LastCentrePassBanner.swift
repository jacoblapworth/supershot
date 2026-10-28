import SwiftUI

package struct LastCentrePassBanner: View {
  package var state: CentrePassConfirmationState
  package var onAction: (ScoringControlAction) -> Void

  package var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 8) {
        Circle().fill(state.team.bibColor).frame(width: 12, height: 12)
          .accessibilityHidden(true)
        Text("Did **\(state.team.name)** take the last centre pass in Quarter \(state.period)?")
          .font(.subheadline)
      }
      HStack(spacing: 10) {
        Button("No, not taken") { onAction(.confirmCentrePass(false)) }
        Button("Yes, pass taken") { onAction(.confirmCentrePass(true)) }
      }
      .buttonSizing(.flexible)
      .buttonStyle(.bordered)
      .fontWeight(.medium)
      .controlSize(.large)
      .disabled(state.availability != .enabled)
      if state.availability == .pending {
        ProgressView("Saving centre pass…").font(.caption)
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
  }
}

#Preview("Centre-pass confirmation") {
  VStack(spacing: 24) {
    ForEach([ScoringControl.Availability.enabled, .pending, .disabled].indices, id: \.self) { index in
      LastCentrePassBanner(state: .init(
        team: .previewSwifts, period: 2,
        availability: [.enabled, .pending, .disabled][index]
      ), onAction: { _ in })
    }
  }.padding()
}
