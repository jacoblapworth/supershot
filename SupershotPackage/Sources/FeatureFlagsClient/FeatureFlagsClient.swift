import Dependencies
import SubscriptionClient

/// Subscription policy only; callers still check platform support and system authorization.
nonisolated package enum ProFeature: CaseIterable, Sendable {
  case liveActivities
  case timerAlerts
}

/// Evaluates a caller's current entitlement without fetching or storing subscription state.
nonisolated package struct FeatureFlagsClient: Sendable {
  package var isEnabled: @Sendable (ProFeature, SubscriptionEntitlement) -> Bool

  package init(isEnabled: @escaping @Sendable (ProFeature, SubscriptionEntitlement) -> Bool) {
    self.isEnabled = isEnabled
  }

  static package var live: Self {
    Self { feature, access in
      switch feature {
      case .liveActivities, .timerAlerts:
        return access == .pro
      }
    }
  }
}

extension DependencyValues {
  nonisolated package var featureFlags: FeatureFlagsClient {
    get { self[FeatureFlagsClientKey.self] }
    set { self[FeatureFlagsClientKey.self] = newValue }
  }
}

private nonisolated enum FeatureFlagsClientKey: DependencyKey {
  static var liveValue: FeatureFlagsClient { .live }
  // The policy is pure and deterministic in every context. Override individual features as needed.
  static var previewValue: FeatureFlagsClient { .live }
  static var testValue: FeatureFlagsClient { .live }
}
