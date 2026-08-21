import ComposableArchitecture
import RevenueCatUI
import SwiftUI

struct ProPaywallView: View {
  let store: StoreOf<ProPaywallFeature>

  var body: some View {
    PaywallView(displayCloseButton: true)
      .onPurchaseCompleted {
        store.send(.customerInfoUpdated(ProAccess(customerInfo: $0)))
      }
      .onRestoreCompleted {
        store.send(.customerInfoUpdated(ProAccess(customerInfo: $0)))
      }
  }
}
