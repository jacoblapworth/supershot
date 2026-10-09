import ComposableArchitecture
import SwiftUI

#if os(iOS)
import UIKit

struct AlarmPermissionCard: View {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openURL) private var openURL
  let store: StoreOf<AlarmPermissionFeature>
  let proAccess: SubscriptionEntitlement
  var hidesWhenAuthorized = false

  var body: some View {
    Group {
      if proAccess != .unknown,
        !(hidesWhenAuthorized && proAccess == .pro && store.authorization == .authorized)
      {
        VStack(alignment: .leading, spacing: 12) {
          if proAccess == .pro, store.authorization == .authorized {
            Label("Alarms enabled", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.secondary)
          } else {
            HStack {
              Label("Never miss the quarter", systemImage: "alarm.fill")
                .font(.headline)
              if proAccess == .free {
                Text("PRO")
                  .font(.caption.bold())
                  .foregroundStyle(Color.accentColor)
              }
            }
            Text("Get an alarm when each quarter or break ends, even when your iPhone is locked.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            if let error = store.errorMessage {
              Text(error).font(.caption).foregroundStyle(.red)
            }
            if store.isRequesting {
              HStack { ProgressView(); Text("Requesting access…") }
            } else if proAccess == .pro, store.authorization == .denied {
              Text("Allow alarms for Supershot in Settings.")
                .font(.caption).foregroundStyle(.secondary)
              Button("Open Settings") {
                openURL(URL(string: UIApplication.openSettingsURLString)!)
              }
              .buttonStyle(.bordered)
            } else {
              Button(proAccess == .free ? "Explore Supershot Pro" : store.errorMessage == nil ? "Enable alarms" : "Try again") {
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
      if phase == .active { store.send(.refresh(proAccess)) }
    }
  }
}
#endif
