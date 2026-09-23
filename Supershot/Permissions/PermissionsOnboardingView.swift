import ComposableArchitecture
import SwiftUI

struct PermissionsOnboardingView: View {
  let store: StoreOf<PermissionsOnboardingFeature>

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        VStack(spacing: 32) {
          PermissionsOnboardingHero(step: store.step)
          PermissionsOnboardingContent(step: store.step)
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
      PermissionsOnboardingActions(store: store)
    }
  }
}

private struct PermissionsOnboardingHero: View {
  var step: PermissionsOnboardingFeature.Step

  var body: some View {
    ZStack {
      Circle()
        .fill(Color.accentColor.opacity(0.12))

      Circle()
        .stroke(Color.accentColor.opacity(0.24), lineWidth: 1)
        .padding(10)

      Image(systemName: step == .alarms ? "alarm.fill" : "location.fill")
        .font(.system(size: 56, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .symbolRenderingMode(.hierarchical)
    }
    .frame(width: 136, height: 136)
    .accessibilityHidden(true)
  }
}

private struct PermissionsOnboardingContent: View {
  var step: PermissionsOnboardingFeature.Step

  var body: some View {
    switch step {
    case .alarms:
      VStack(spacing: 32) {
        PermissionsOnboardingHeading(
          description: "Allow Supershot to alert you when each quarter ends, even when your iPhone is locked or Supershot isn’t on screen.",
          title: "Never miss the quarter."
        )
        VStack(spacing: 12) {
          PermissionsOnboardingBenefit(
            description: "Know exactly when play should stop.",
            systemImage: "sportscourt.fill",
            title: "Quarter-end alerts"
          )
          PermissionsOnboardingBenefit(
            description: "Keep the game moving while Supershot is off-screen.",
            systemImage: "iphone.and.arrow.forward",
            title: "Works in the background"
          )
        }
      }

    case .location:
      VStack(spacing: 32) {
        PermissionsOnboardingHeading(
          description: "Allow Supershot to record where each game is played and label it with a nearby place.",
          title: "Remember every venue."
        )
        VStack(spacing: 12) {
          PermissionsOnboardingBenefit(
            description: "See the venue while setting up a game.",
            systemImage: "map.fill",
            title: "Confirm the location"
          )
          PermissionsOnboardingBenefit(
            description: "Look back at where completed games were played.",
            systemImage: "clock.arrow.circlepath",
            title: "Keep the context"
          )
        }
      }
    }
  }
}

private struct PermissionsOnboardingHeading: View {
  var description: LocalizedStringResource
  var title: LocalizedStringResource

  var body: some View {
    VStack(spacing: 12) {
      Text(title)
        .font(.largeTitle.bold())
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      Text(description)
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct PermissionsOnboardingBenefit: View {
  var description: LocalizedStringResource
  var systemImage: String
  var title: LocalizedStringResource

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

private struct PermissionsOnboardingActions: View {
  let store: StoreOf<PermissionsOnboardingFeature>

  var body: some View {
    VStack(spacing: 10) {
      if let errorMessage = store.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Button {
        store.send(.allowButtonTapped)
      } label: {
        if store.isRequesting {
          HStack {
            ProgressView()
            Text("Requesting access…")
          }
          .frame(maxWidth: .infinity)
        } else {
          Label(
            store.step == .alarms ? "Allow alarms" : "Allow location",
            systemImage: store.step == .alarms ? "alarm.fill" : "location.fill"
          )
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

      Text(footer)
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

  private var footer: LocalizedStringResource {
    switch store.step {
    case .alarms:
      "Supershot only creates alarms for games you start. Change this any time in Settings."
    case .location:
      "Supershot only records a location when you set up a new game. Change this any time in Settings."
    }
  }
}

#Preview("Alarm onboarding") {
  PermissionsOnboardingView(
    store: Store(initialState: PermissionsOnboardingFeature.State()) {
      PermissionsOnboardingFeature()
    }
  )
}

#Preview("Location onboarding") {
  PermissionsOnboardingView(
    store: Store(
      initialState: PermissionsOnboardingFeature.State(step: .location)
    ) {
      PermissionsOnboardingFeature()
    }
  )
}
