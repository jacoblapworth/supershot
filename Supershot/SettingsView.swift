import RevenueCatUI
import Sharing
import SwiftUI
import RevenueCat

struct SettingsView: View {
  let proAccess: SubscriptionEntitlement
  var proAccessUpdated: (SubscriptionEntitlement) -> Void
  var proPromotionTapped: () -> Void
  
#if os(iOS)
  @State private var isCustomerCenterPresented = false
#else
  @Environment(\.openURL) private var openURL
#endif
  
  var body: some View {
#if os(iOS)
    SettingsContent(
      proAccess: proAccess,
      manageSubscriptionTapped: { isCustomerCenterPresented = true },
      proPromotionTapped: proPromotionTapped
    )
    .presentCustomerCenter(
      isPresented: $isCustomerCenterPresented,
      restoreCompleted: { proAccessUpdated(SubscriptionEntitlement(customerInfo: $0)) },
      onDismiss: { isCustomerCenterPresented = false }
    )
#else
    SettingsContent(
      proAccess: proAccess,
      manageSubscriptionTapped: {
        openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
      },
      proPromotionTapped: proPromotionTapped
    )
#endif
  }
}

private struct SettingsContent: View {
  let proAccess: SubscriptionEntitlement
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
      GameDefaultsSettingsSection()
    }
    .navigationTitle("Settings")
  }
}

private struct SubscriptionSettingsSection: View {
  let proAccess: SubscriptionEntitlement
  var manageSubscriptionTapped: () -> Void
  var proPromotionTapped: () -> Void
  
  @State private var debugOverlayVisible: Bool = false
  
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
      
#if DEBUG
      Button {
        self.debugOverlayVisible = true
      } label: {
        Label("Debug", systemImage: "flask.fill")
      }
      .debugRevenueCatOverlay(isPresented: self.$debugOverlayVisible)
#endif
    }
  }
}

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
  @Shared(.defaultBreakDurationSeconds) private var defaultBreakDurationSeconds
  @Shared(.defaultPeriodDurationSeconds) private var defaultPeriodDurationSeconds
  
  var body: some View {
    Section {
      Picker(
        selection: Binding($defaultPeriodDurationSeconds)
      ) {
        Text("8 minutes").tag(8 * 60)
        Text("10 minutes").tag(10 * 60)
        Text("12 minutes").tag(12 * 60)
        Text("15 minutes").tag(15 * 60)
      } label: {
        Label("Quarter length", systemImage: "timer")
      }
      
      Picker(
        selection: Binding($defaultBreakDurationSeconds)
      ) {
        Text("No break").tag(0)
        Text("1 minute").tag(1 * 60)
        Text("2 minutes").tag(2 * 60)
        Text("4 minutes").tag(4 * 60)
        Text("5 minutes").tag(5 * 60)
      } label: {
        Label("Break length", systemImage: "pause.circle")
      }
    } header: {
      Text("New game defaults")
    } footer: {
      Text("These times are used when you set up a new game and can still be changed before it starts.")
    }
  }
}

#Preview("Free") {
  NavigationStack {
    SettingsView(
      proAccess: .free,
      proAccessUpdated: { _ in },
      proPromotionTapped: {}
    )
  }
}

#Preview("Pro") {
  NavigationStack {
    SettingsView(
      proAccess: .pro,
      proAccessUpdated: { _ in },
      proPromotionTapped: {}
    )
  }
}
