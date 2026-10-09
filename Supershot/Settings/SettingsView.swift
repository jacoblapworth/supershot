import ComposableArchitecture
import RevenueCatUI
import Sharing
import SwiftUI
import RevenueCat

struct SettingsView: View {
  let proAccess: SubscriptionEntitlement
  @Bindable var store: StoreOf<SettingsFeature>
  
#if !os(iOS)
  @Environment(\.openURL) private var openURL
#endif
  
  var body: some View {
    NavigationStack {
#if os(iOS)
      SettingsContent(
        proAccess: proAccess,
        store: store,
        manageSubscriptionTapped: { store.send(.manageSubscriptionButtonTapped) },
        proPromotionTapped: { store.send(.proPromotionTapped) }
      )
      .presentCustomerCenter(
        isPresented: $store.isCustomerCenterPresented.sending(
          \.customerCenterPresentationChanged
        ),
        restoreCompleted: {
          store.send(
            .customerInfoUpdated(SubscriptionEntitlement(customerInfo: $0))
          )
        },
        onDismiss: { store.send(.customerCenterPresentationChanged(false)) }
      )
#else
      SettingsContent(
        proAccess: proAccess,
        store: store,
        manageSubscriptionTapped: {
          openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
        },
        proPromotionTapped: { store.send(.proPromotionTapped) }
      )
#endif
    }
    .sheet(item: $store.scope(state: \.timeInput, action: \.timeInput)) { TimeInputView(store: $0) }
  }
}

private struct SettingsContent: View {
  let proAccess: SubscriptionEntitlement
  let store: StoreOf<SettingsFeature>
  var manageSubscriptionTapped: () -> Void
  var proPromotionTapped: () -> Void
  
  var body: some View {
    Form {
      SubscriptionSettingsSection(
        proAccess: proAccess,
        manageSubscriptionTapped: manageSubscriptionTapped,
        proPromotionTapped: proPromotionTapped
      )
      FeedbackSettingsSection()
      GameDefaultsSettingsSection(store: store)
#if DEBUG
      DebugSettingsSection(store: store)
#endif
    }
    .navigationTitle("Settings")
  }
}

private struct SubscriptionSettingsSection: View {
  let proAccess: SubscriptionEntitlement
  var manageSubscriptionTapped: () -> Void
  var proPromotionTapped: () -> Void
  
  var body: some View {
    Section("Subscription") {
      LabeledContent {
        switch proAccess {
        case .free:
          Text("Free")
            .foregroundStyle(.secondary)
        case .pro:
          Text("Active")
            .foregroundStyle(.green)
        case .unknown:
          ProgressView()
            .controlSize(.small)
        }
      } label: {
        Label("Supershot Pro", systemImage: "star.fill")
      }
      
      switch proAccess {
      case .free:
        Button(action: proPromotionTapped) {
          Label("View Supershot Pro", systemImage: "sparkles")
        }
      case .pro:
        Button(action: manageSubscriptionTapped) {
          Label("Manage subscription", systemImage: "person.crop.circle")
        }
      case .unknown:
        Button("Checking subscription…") {}
          .disabled(true)
      }
    }
  }
}

#if DEBUG
private struct DebugSettingsSection: View {
  @Bindable var store: StoreOf<SettingsFeature>
  @State private var debugOverlayVisible = false

  var body: some View {
    Section {
      Button {
        store.send(.exportDatabaseButtonTapped)
      } label: {
        HStack {
          Label("Export SQLite database", systemImage: "square.and.arrow.up")
          if store.databaseExport == .preparing {
            Spacer()
            ProgressView()
          }
        }
      }
      .disabled(store.databaseExport != nil)

      Button {
        debugOverlayVisible = true
      } label: {
        Label("Subscription debugger", systemImage: "flask.fill")
      }
      .debugRevenueCatOverlay(isPresented: $debugOverlayVisible)
    } header: {
      Text("Debug")
    } footer: {
      Text("Export a snapshot of all teams, games, and goals for inspection.")
    }
    .sheet(
      isPresented: $store.isDatabaseSharePresented.sending(
        \.databaseSharePresentationChanged
      )
    ) {
      if case let .ready(url) = store.databaseExport {
        DatabaseShareSheet(url: url) {
          store.send(.databaseShareCompleted($0))
        }
#if os(macOS)
        .frame(width: 320, height: 120)
#endif
      }
    }
    .alert($store.scope(state: \.alert, action: \.alert))
  }

}
#endif

private struct FeedbackSettingsSection: View {
  @Shared(.hapticsEnabled) private var hapticsEnabled
  @Shared(.soundEffectsEnabled) private var soundEffectsEnabled
  
  var body: some View {
    Section {
      Toggle(isOn: Binding($soundEffectsEnabled)) {
        Label("Goal sounds", systemImage: "speaker.wave.2")
      }
      Toggle(isOn: Binding($hapticsEnabled)) {
        Label("Goal haptics", systemImage: "iphone.radiowaves.left.and.right")
      }
    } header: {
      Text("Feedback")
    } footer: {
      Text("Choose the feedback played when a goal is recorded.")
    }
  }
}

private struct GameDefaultsSettingsSection: View {
  let store: StoreOf<SettingsFeature>
  
  var body: some View {
    Section {
      durationRow("Quarter length", seconds: store.defaultPeriodDurationSeconds, field: .quarter)
      durationRow("Break length", seconds: store.defaultBreakDurationSeconds, field: .breakTime)
    } header: {
      Text("New game defaults")
    } footer: {
      Text("These times are used when you set up a new game and can still be changed before it starts.")
    }
  }
  private func durationRow(_ title: String, seconds: Int, field: SettingsFeature.DurationDefault)
    -> some View
  {
    HStack {
      Text(title)
      Spacer()
      Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
        .monospacedDigit().foregroundStyle(.secondary)
      Button("Edit") { store.send(.editDefaultButtonTapped(field)) }
        .accessibilityLabel("Edit \(title)")
    }
  }
}

#Preview("Free") {
  NavigationStack {
    SettingsView(
      proAccess: .free,
      store: Store(initialState: SettingsFeature.State()) {
        SettingsFeature()
      }
    )
  }
}

#Preview("Pro") {
  NavigationStack {
    SettingsView(
      proAccess: .pro,
      store: Store(initialState: SettingsFeature.State()) {
        SettingsFeature()
      }
    )
  }
}
