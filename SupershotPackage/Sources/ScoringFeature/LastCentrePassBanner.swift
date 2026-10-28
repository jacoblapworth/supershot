import SwiftUI

package struct LastCentrePassBanner: View {
  package var state: CentrePassConfirmationState
  package var onAction: (ScoringControlAction) -> Void
  @State package var taken = true
  
  package var body: some View {
    HStack(spacing: 12) {
      Text("Centre pass taken?")
        .font(.headline)
        .padding(.leading, 16)
      Spacer()
      Picker(selection: $taken) {
        Text("Yes")
          .tag(true)
        Text("No")
          .tag(false)
      } label: {
        Text("Centre pass taken?")
      }
      .disabled(state.availability != .enabled)
      .tint(.blue)
      .pickerStyle(.segmented)
      .fixedSize()

      Button {
        onAction(.confirmCentrePass(taken))
      } label: {
        ZStack {
          if state.availability == .pending {
            ProgressView()
              .controlSize(.regular)
          }
          Label("Confirm", systemImage: "checkmark")
        }
      }
      .disabled(state.availability == .pending)
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.circle)
      .labelStyle(.iconOnly)
    }
    .padding(8)
    .frame(maxWidth: .infinity)
    .controlSize(.large)
    .accessibilityElement(children: .contain)
    .background(Material.thick, in: RoundedRectangle(cornerRadius: 32))
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
