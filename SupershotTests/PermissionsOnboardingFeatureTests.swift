import ComposableArchitecture
import ConcurrencyExtras
import CustomDump
import Dependencies
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct PermissionsOnboardingFeatureTests {
    @Test
    func proOnboardingPresentsAlarmsThenLocation() async {
      let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.alarmAuthorization = AlarmAuthorizationClient(
          request: { .notDetermined },
          status: { .notDetermined }
        )
        $0.locationClient = LocationClient(
          authorizationStatus: { .notDetermined },
          currentLocation: { throw LocationClientError.locationUnavailable },
          requestAuthorization: { .notDetermined }
        )
      }

      await store.send(.task) {
        $0.hasStartedSubscriptionObservation = true
      }
      await store.receive {
        guard case .proAccessLoaded(.pro) = $0 else { return false }
        return true
      } assert: {
        $0.hasCheckedPermissions = true
        $0.permissionsOnboarding = PermissionsOnboardingFeature.State(
          nextStep: .location
        )
        $0.proAccess = .pro
      }
      await store.finish()
    }

    @Test
    func freeOnboardingPresentsLocationOnly() async {
      let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.locationClient = LocationClient(
          authorizationStatus: { .notDetermined },
          currentLocation: { throw LocationClientError.locationUnavailable },
          requestAuthorization: { .notDetermined }
        )
        $0.proSubscription = ProSubscriptionClient(
          accessUpdates: { AsyncStream { $0.finish() } },
          currentAccess: { .free }
        )
      }

      await store.send(.task) {
        $0.hasStartedSubscriptionObservation = true
      }
      await store.receive {
        guard case .proAccessLoaded(.free) = $0 else { return false }
        return true
      } assert: {
        $0.hasCheckedPermissions = true
        $0.permissionsOnboarding = PermissionsOnboardingFeature.State(step: .location)
        $0.proAccess = .free
      }
      await store.finish()
    }

    @Test
    func onboardingIsSkippedWhenPermissionsAreResolved() async {
      let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.alarmAuthorization = .authorized
        $0.locationClient = .preview
      }

      await store.send(.task) {
        $0.hasStartedSubscriptionObservation = true
      }
      await store.receive {
        guard case .proAccessLoaded(.pro) = $0 else { return false }
        return true
      } assert: {
        $0.hasCheckedPermissions = true
        $0.proAccess = .pro
      }
      await store.finish()
      expectNoDifference(store.state.permissionsOnboarding, nil)
    }

    @Test
    func allowingAlarmAdvancesToLocation() async {
      var state = PermissionsOnboardingFeature.State(nextStep: .location)
      let store = TestStore(initialState: state) {
        PermissionsOnboardingFeature()
      } withDependencies: {
        $0.alarmAuthorization = .authorized
      }

      await store.send(.allowButtonTapped) {
        $0.isRequesting = true
      }
      await store.receive {
        guard case .authorizationResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.isRequesting = false
        $0.nextStep = nil
        $0.step = .location
      }
    }

    @Test
    func allowingLocationCompletesOnboarding() async {
      let requests = LockIsolated(0)
      let store = TestStore(
        initialState: PermissionsOnboardingFeature.State(step: .location)
      ) {
        PermissionsOnboardingFeature()
      } withDependencies: {
        $0.locationClient = LocationClient(
          authorizationStatus: { .notDetermined },
          currentLocation: { throw LocationClientError.locationUnavailable },
          requestAuthorization: {
            requests.withValue { $0 += 1 }
            return .authorized
          }
        )
      }

      await store.send(.allowButtonTapped) {
        $0.isRequesting = true
      }
      await store.receive {
        guard case .authorizationResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.isRequesting = false
      }
      await store.receive {
        guard case .delegate(.completed) = $0 else { return false }
        return true
      }
      expectNoDifference(requests.value, 1)
    }

    @Test
    func notNowAdvancesThenCompletesWithoutRequests() async {
      var state = PermissionsOnboardingFeature.State(nextStep: .location)
      let store = TestStore(initialState: state) {
        PermissionsOnboardingFeature()
      }

      await store.send(.notNowButtonTapped) {
        $0.nextStep = nil
        $0.step = .location
      }
      await store.send(.notNowButtonTapped)
      await store.receive {
        guard case .delegate(.completed) = $0 else { return false }
        return true
      }
    }

    @Test
    func alarmRequestFailureCanBeRetried() async {
      let attempts = LockIsolated(0)
      let store = TestStore(initialState: PermissionsOnboardingFeature.State()) {
        PermissionsOnboardingFeature()
      } withDependencies: {
        $0.alarmAuthorization = AlarmAuthorizationClient(
          request: {
            let attempt = attempts.withValue {
              $0 += 1
              return $0
            }
            guard attempt > 1 else { throw PermissionAuthorizationTestError.failed }
            return .authorized
          },
          status: { .notDetermined }
        )
      }

      await store.send(.allowButtonTapped) {
        $0.isRequesting = true
      }
      await store.receive {
        guard case .authorizationResponse(.failure) = $0 else { return false }
        return true
      } assert: {
        $0.errorMessage = "Supershot couldn’t request alarm access. Try again."
        $0.isRequesting = false
      }

      await store.send(.allowButtonTapped) {
        $0.errorMessage = nil
        $0.isRequesting = true
      }
      await store.receive {
        guard case .authorizationResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.isRequesting = false
      }
      await store.receive {
        guard case .delegate(.completed) = $0 else { return false }
        return true
      }

      expectNoDifference(attempts.value, 2)
    }

    @Test
    func completingOnboardingRevealsGames() async {
      var state = AppFeature.State()
      state.hasCheckedPermissions = true
      state.permissionsOnboarding = PermissionsOnboardingFeature.State(step: .location)

      let store = TestStore(initialState: state) {
        AppFeature()
      }

      await store.send(.permissionsOnboarding(.presented(.notNowButtonTapped)))
      await store.receive {
        guard case .permissionsOnboarding(.presented(.delegate(.completed))) = $0 else {
          return false
        }
        return true
      } assert: {
        $0.permissionsOnboarding = nil
      }
    }
  }
}

private nonisolated enum PermissionAuthorizationTestError: Error {
  case failed
}
