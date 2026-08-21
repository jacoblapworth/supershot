import ComposableArchitecture
import ConcurrencyExtras
import CustomDump
import Dependencies
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct AlarmOnboardingFeatureTests {
    @Test
    func alarmOnboardingAppearsWhenAuthorizationIsNotDetermined() async {
      let statusChecks = LockIsolated(0)
      let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.alarmAuthorization = AlarmAuthorizationClient(
          request: { .notDetermined },
          status: {
            statusChecks.withValue { $0 += 1 }
            return .notDetermined
          }
        )
      }

      await store.send(.task) {
        $0.hasStartedSubscriptionObservation = true
      }
      await store.receive {
        guard case .proAccessLoaded(.pro) = $0 else { return false }
        return true
      } assert: {
        $0.alarmOnboarding = AlarmOnboardingFeature.State()
        $0.hasCheckedAlarmAuthorization = true
        $0.proAccess = .pro
      }
      await store.send(.task)
      await store.finish()

      expectNoDifference(statusChecks.value, 1)
    }

    @Test
    func alarmOnboardingIsSkippedWhenAuthorizationIsResolved() async {
      for expectedStatus in [AlarmAuthorizationStatus.authorized, .denied] {
        let store = TestStore(initialState: AppFeature.State()) {
          AppFeature()
        } withDependencies: {
          $0.alarmAuthorization = AlarmAuthorizationClient(
            request: { expectedStatus },
            status: { expectedStatus }
          )
        }

        await store.send(.task) {
          $0.hasStartedSubscriptionObservation = true
        }
        await store.receive {
          guard case .proAccessLoaded(.pro) = $0 else { return false }
          return true
        } assert: {
          $0.hasCheckedAlarmAuthorization = true
          $0.proAccess = .pro
        }
        await store.finish()
        expectNoDifference(store.state.alarmOnboarding, nil)
      }
    }

    @Test
    func alarmOnboardingCompletesAfterAuthorizationIsResolved() async {
      for expectedStatus in [AlarmAuthorizationStatus.authorized, .denied] {
        let requests = LockIsolated(0)
        let store = TestStore(initialState: AlarmOnboardingFeature.State()) {
          AlarmOnboardingFeature()
        } withDependencies: {
          $0.alarmAuthorization = AlarmAuthorizationClient(
            request: {
              requests.withValue { $0 += 1 }
              return expectedStatus
            },
            status: { expectedStatus }
          )
        }

        await store.send(.allowAlarmsButtonTapped) {
          $0.isRequesting = true
        }
        await store.receive {
          guard case let .authorizationResponse(.success(status)) = $0 else {
            return false
          }
          return status == expectedStatus
        } assert: {
          $0.isRequesting = false
        }
        await store.receive {
          guard case .delegate(.completed) = $0 else { return false }
          return true
        }

        expectNoDifference(requests.value, 1)
      }
    }

    @Test
    func alarmOnboardingCanBeSkippedWithoutRequestingAuthorization() async {
      let requests = LockIsolated(0)
      let store = TestStore(initialState: AlarmOnboardingFeature.State()) {
        AlarmOnboardingFeature()
      } withDependencies: {
        $0.alarmAuthorization = AlarmAuthorizationClient(
          request: {
            requests.withValue { $0 += 1 }
            return .authorized
          },
          status: { .notDetermined }
        )
      }

      await store.send(.notNowButtonTapped)
      await store.receive {
        guard case .delegate(.completed) = $0 else { return false }
        return true
      }

      expectNoDifference(requests.value, 0)
    }

    @Test
    func completingAlarmOnboardingRevealsGames() async {
      var state = AppFeature.State()
      state.alarmOnboarding = AlarmOnboardingFeature.State()
      state.hasCheckedAlarmAuthorization = true

      let store = TestStore(initialState: state) {
        AppFeature()
      }

      await store.send(.alarmOnboarding(.presented(.notNowButtonTapped)))
      await store.receive {
        guard case .alarmOnboarding(.presented(.delegate(.completed))) = $0 else {
          return false
        }
        return true
      } assert: {
        $0.alarmOnboarding = nil
      }
    }

    @Test
    func alarmOnboardingRequestFailureCanBeRetried() async {
      let attempts = LockIsolated(0)
      let store = TestStore(initialState: AlarmOnboardingFeature.State()) {
        AlarmOnboardingFeature()
      } withDependencies: {
        $0.alarmAuthorization = AlarmAuthorizationClient(
          request: {
            let attempt = attempts.withValue {
              $0 += 1
              return $0
            }
            guard attempt > 1 else { throw AlarmAuthorizationTestError.failed }
            return .authorized
          },
          status: { .notDetermined }
        )
      }

      await store.send(.allowAlarmsButtonTapped) {
        $0.isRequesting = true
      }
      await store.receive {
        guard case .authorizationResponse(.failure) = $0 else { return false }
        return true
      } assert: {
        $0.errorMessage = "Supershot couldn’t request alarm access. Try again."
        $0.isRequesting = false
      }

      await store.send(.allowAlarmsButtonTapped) {
        $0.errorMessage = nil
        $0.isRequesting = true
      }
      await store.receive {
        guard case .authorizationResponse(.success(.authorized)) = $0 else {
          return false
        }
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
  }
}

private nonisolated enum AlarmAuthorizationTestError: Error {
  case failed
}
