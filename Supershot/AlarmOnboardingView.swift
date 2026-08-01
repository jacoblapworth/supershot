import ComposableArchitecture
import SwiftUI

struct AlarmOnboardingView: View {
  let store: StoreOf<AlarmOnboardingFeature>

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        VStack(spacing: 32) {
          AlarmOnboardingHero()

          VStack(spacing: 12) {
            Text("Never miss the quarter.")
              .font(.largeTitle.bold())
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityAddTraits(.isHeader)

            Text(
              "Allow Supershot to alert you when each quarter ends, "
                + "even when your iPhone is locked or Supershot isn’t on screen."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
          }

          VStack(spacing: 12) {
            AlarmOnboardingBenefit(
              description: "Know exactly when play should stop.",
              systemImage: "sportscourt.fill",
              title: "Quarter-end alerts"
            )
            AlarmOnboardingBenefit(
              description: "Keep the game moving while Supershot is off-screen.",
              systemImage: "iphone.and.arrow.forward",
              title: "Works in the background"
            )
          }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
      }
    }
    .background {
      LinearGradient(
        colors: [Color.accentColor.opacity(0.16), .clear],
        startPoint: .top,
        endPoint: .center
      )
      .ignoresSafeArea()
    }
    .safeAreaInset(edge: .bottom) {
      AlarmOnboardingActions(store: store)
    }
  }
}

private struct AlarmOnboardingHero: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(Color.accentColor.opacity(0.12))

      Circle()
        .stroke(Color.accentColor.opacity(0.24), lineWidth: 1)
        .padding(10)

      Image(systemName: "alarm.fill")
        .font(.system(size: 56, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .symbolRenderingMode(.hierarchical)
    }
    .frame(width: 136, height: 136)
    .accessibilityHidden(true)
  }
}

private struct AlarmOnboardingBenefit: View {
  var description: String
  var systemImage: String
  var title: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: systemImage)
        .font(.title3.weight(.semibold))
        .foregroundStyle(Color.accentColor)
        .frame(width: 32, height: 32)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
  }
}

private struct AlarmOnboardingActions: View {
  let store: StoreOf<AlarmOnboardingFeature>

  var body: some View {
    VStack(spacing: 10) {
      if let errorMessage = store.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Button {
        store.send(.allowAlarmsButtonTapped)
      } label: {
        if store.isRequesting {
          HStack {
            ProgressView()
            Text("Requesting access…")
          }
          .frame(maxWidth: .infinity)
        } else {
          Label("Allow alarms", systemImage: "alarm.fill")
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(store.isRequesting)

      Button("Not now") {
        store.send(.notNowButtonTapped)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .disabled(store.isRequesting)

      Text("Supershot only creates alarms for games you start. Change this any time in Settings.")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: 520)
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity)
    .background(.bar)
  }
}

#Preview("Alarm onboarding") {
  AlarmOnboardingView(
    store: Store(initialState: AlarmOnboardingFeature.State()) {
      AlarmOnboardingFeature()
    }
  )
}

#Preview("Request failed") {
  AlarmOnboardingView(
    store: Store(
      initialState: AlarmOnboardingFeature.State(
        errorMessage: "Supershot couldn’t request alarm access. Try again."
      )
    ) {
      AlarmOnboardingFeature()
    }
  )
  .preferredColorScheme(.dark)
  .environment(\.dynamicTypeSize, .accessibility2)
}
