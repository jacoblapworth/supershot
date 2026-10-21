import CustomDump
import Dependencies
import DependenciesTestSupport
import FeatureFlagsClient
import SubscriptionClient
import Testing

struct FeatureFlagsClientTests {
  @Test(arguments: ProFeature.allCases, [SubscriptionEntitlement.free, .pro, .unknown])
  func defaultPolicy(feature: ProFeature, access: SubscriptionEntitlement) {
    expectNoDifference(FeatureFlagsClient.live.isEnabled(feature, access), access == .pro)
  }

  @Test func independentOverridesStayWithinDependencyScope() {
    withDependencies {
      $0.featureFlags = FeatureFlagsClient { feature, _ in feature == .liveActivities }
    } operation: {
      @Dependency(\.featureFlags) var flags
      expectNoDifference(flags.isEnabled(.liveActivities, .free), true)
      expectNoDifference(flags.isEnabled(.timerAlerts, .pro), false)
    }
    @Dependency(\.featureFlags) var flags
    expectNoDifference(flags.isEnabled(.liveActivities, .free), false)
    expectNoDifference(flags.isEnabled(.timerAlerts, .pro), true)
  }
}
