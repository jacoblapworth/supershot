import AlarmClient
import ComposableArchitecture
import FeatureFlagsClient
import Styleguide
import SubscriptionClient
import SwiftUI

#if os(iOS)
  import UIKit
#endif

package struct AlarmPermissionCard: View {
  @Dependency(\.featureFlags) private var featureFlags
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openURL) private var openURL
  package let store: StoreOf<AlarmPermissionFeature>
  package let proAccess: SubscriptionEntitlement
  package var hidesWhenAuthorized = false
  package var showsHeading = true

  package var body: some View {
    Group {
      if proAccess != .unknown,
         !(hidesWhenAuthorized && timerAlertsEnabled && store.authorization == .authorized)
      {
        VStack(alignment: .leading, spacing: 12) {
          if timerAlertsEnabled, store.authorization == .authorized {
            #if os(macOS)
              Label("Notifications enabled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
            #else
              Label("Alarms enabled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
            #endif
          } else {
            HStack {
              if showsHeading {
                Label("Never miss the quarter", systemImage: "alarm.fill")
                  .font(.headline)
              }
              if !timerAlertsEnabled {
                Text("PRO")
                  .font(.caption.bold())
                  .foregroundStyle(Color.accentColor)
              }
            }
            #if os(macOS)
              Text(
                "Get a notification when each quarter or break ends. Delivery follows your Mac’s notification and Focus settings."
              )
              .font(.subheadline)
              .foregroundStyle(.secondary)
            #else
              Text("Get an alarm when each quarter or break ends, even when your iPhone is locked.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            #endif
            if let error = store.errorMessage {
              Text(error).font(.caption).foregroundStyle(.red)
            }
            if store.isRequesting {
              HStack {
                ProgressView()
                Text("Requesting access…")
              }
            } else if timerAlertsEnabled, store.authorization == .denied {
              #if os(macOS)
                Text("Allow notifications for Supershot in System Settings → Notifications.")
                  .font(.caption).foregroundStyle(.secondary)
              #else
                Text("Allow alarms for Supershot in Settings.")
                  .font(.caption).foregroundStyle(.secondary)
              #endif
              Button("Open Settings") {
                #if os(macOS)
                  openURL(
                    URL(
                      string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
                    )!
                  )
                #else
                  openURL(URL(string: UIApplication.openSettingsURLString)!)
                #endif
              }
              .buttonStyle(.bordered)
            } else {
              Button(
                !timerAlertsEnabled
                  ? "Explore Supershot Pro"
                  : store.errorMessage == nil ? enableTitle : "Try again"
              ) {
                store.send(.enableButtonTapped)
              }
              .buttonStyle(.bordered)
            }
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .setupCardStyle()
      }
    }
    .task(id: proAccess) { store.send(.refresh(proAccess)) }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        store.send(.refresh(proAccess))
      }
    }
  }

  private var timerAlertsEnabled: Bool {
    featureFlags.isEnabled(.timerAlerts, proAccess)
  }

  private var enableTitle: String {
    #if os(macOS)
      "Enable notifications"
    #else
      "Enable alarms"
    #endif
  }

  package init(
    store: StoreOf<AlarmPermissionFeature>, proAccess: SubscriptionEntitlement,
    hidesWhenAuthorized: Bool = false, showsHeading: Bool = true
  ) {
    self.store = store
    self.proAccess = proAccess
    self.hidesWhenAuthorized = hidesWhenAuthorized
    self.showsHeading = showsHeading
  }
}
