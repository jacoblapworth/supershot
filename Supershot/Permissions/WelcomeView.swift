import ComposableArchitecture
import SwiftUI

struct WelcomeView: View {
  let store: StoreOf<WelcomeFeature>

  var body: some View {
    ScrollView {
      VStack(spacing: 32) {
        WelcomeHeader()
        VStack(spacing: 12) {
          WelcomeBenefit(
            title: "Score with confidence",
            detail: "Track goals and the next centre pass.",
            symbol: "sportscourt.fill"
          )
          WelcomeBenefit(
            title: "Keep game day organised",
            detail: "Save teams, customise quarters and breaks, and revisit games.",
            symbol: "person.2.fill"
          )
          WelcomeBenefit(
            title: "Follow every quarter",
            detail: "Follow the score with Live Activities and get quarter and break alarms.",
            symbol: "alarm.fill",
            isPro: true
          )
        }
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 32)
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity)
    }
    .background {
      LinearGradient(
        colors: [Color.accentColor.opacity(0.16), .clear],
        startPoint: .top, endPoint: .center
      )
      .ignoresSafeArea()
    }
    .safeAreaInset(edge: .bottom) {
      Button("Get started") { store.send(.getStartedButtonTapped) }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonSizing(.flexible)
        .frame(maxWidth: 472)
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
  }
}

private struct WelcomeHeader: View {
  var body: some View {
    VStack(spacing: 16) {
      Image("WelcomeIcon")
        .resizable()
        .scaledToFit()
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityHidden(true)
      Text("Supershot")
        .font(.title2.bold())
        .foregroundStyle(Color.accentColor)
      Text("Keep your focus on the game.")
        .font(.largeTitle.bold())
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
    }
  }
}

private struct WelcomeBenefit: View {
  let title: LocalizedStringKey
  let detail: LocalizedStringKey
  let symbol: String
  var isPro = false

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: symbol)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(.headline)
        if isPro {
          Text("PRO")
            .font(.caption.bold())
            .foregroundStyle(Color.accentColor)
        }
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  WelcomeView(store: Store(initialState: WelcomeFeature.State()) { WelcomeFeature() })
}
