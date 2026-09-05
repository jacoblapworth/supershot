import ComposableArchitecture
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct SettingsFeatureTests {
    @Test
    func customerCenterPresentationIsFeatureOwned() async {
      let store = TestStore(initialState: SettingsFeature.State()) {
        SettingsFeature()
      }

      await store.send(.manageSubscriptionButtonTapped) {
        $0.isCustomerCenterPresented = true
      }
      await store.send(.customerCenterPresentationChanged(false)) {
        $0.isCustomerCenterPresented = false
      }
    }

    @Test
    func subscriptionActionsDelegateToApp() async {
      let store = TestStore(initialState: SettingsFeature.State()) {
        SettingsFeature()
      }

      await store.send(.proPromotionTapped)
      await store.receive {
        guard case .delegate(.proPromotionTapped) = $0 else { return false }
        return true
      }

      await store.send(.customerInfoUpdated(.pro))
      await store.receive {
        guard case .delegate(.proAccessChanged(.pro)) = $0 else { return false }
        return true
      }
    }
  }
}
