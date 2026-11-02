import SwiftUI

package struct LastCentrePassBanner: View {
  package var state: CentrePassConfirmationState
  package var onAction: (ScoringControlAction) -> Void
  @State package var taken = true
  @State private var confirmationDeadline: ContinuousClock.Instant?
  @State private var hasSubmitted = false

  private let confirmationTimeout: Duration = .seconds(15)

  package var body: some View {
    HStack(spacing: 12) {
      Text("Centre pass taken?")
        .font(.headline)
        .padding(.leading, 16)
        .fixedSize()
      Spacer()
      Picker(selection: $taken) {
        Text("Yes")
          .tag(true)
        Text("No")
          .tag(false)
      } label: {
        Text("Centre pass taken?")
      }
      .disabled(state.availability != .enabled || hasSubmitted)
      .tint(.blue)
      .pickerStyle(.segmented)

      Button {
        confirm()
      } label: {
        ZStack {
          if state.availability == .pending {
            ProgressView()
              .controlSize(.regular)
          }
          Label("Confirm", systemImage: "checkmark")
            .opacity(state.availability == .pending ? 0 : 1)
        }
      }
      .disabled(state.availability != .enabled || hasSubmitted)
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.circle)
      .labelStyle(.iconOnly)
      .accessibilityHint("Automatically confirms the selected option after 15 seconds.")
      .overlay {
        if let confirmationDeadline, !hasSubmitted {
          TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            let remaining = ContinuousClock.now.duration(to: confirmationDeadline) / confirmationTimeout

            Circle()
              .trim(from: 0, to: min(1, max(0, remaining)))
              .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
              .rotationEffect(.degrees(-90))
              .padding(2)
          }
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity)
    .controlSize(.large)
    .accessibilityElement(children: .contain)
    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 32))
    .task(id: state) {
      confirmationDeadline = nil
      guard state.availability == .enabled else { return }

      hasSubmitted = false
      let deadline = ContinuousClock.now.advanced(by: confirmationTimeout)
      confirmationDeadline = deadline

      do {
        try await ContinuousClock().sleep(until: deadline)
        try Task.checkCancellation()
        confirm()
      } catch is CancellationError {
        // Leaving the banner or changing availability cancels automatic confirmation.
      } catch {
        assertionFailure("Unexpected confirmation timer error: \(error)")
      }
    }
//    .background(Material.thick, in: RoundedRectangle(cornerRadius: 32))
  }

  private func confirm() {
    guard state.availability == .enabled, !hasSubmitted else { return }
    hasSubmitted = true
    confirmationDeadline = nil
    onAction(.confirmCentrePass(taken))
  }
}

#Preview("Centre-pass confirmation") {
  VStack(spacing: 24) {
    ForEach([ScoringControl.Availability.enabled, .pending, .disabled].indices, id: \.self) { index in
      LastCentrePassBanner(state: .init(
        team: .previewSwifts,
        period: 2,
        availability: [.enabled, .pending, .disabled][index]
      ), onAction: { _ in })
    }
  }.padding()
}
