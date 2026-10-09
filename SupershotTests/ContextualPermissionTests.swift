import ComposableArchitecture
import Dependencies
import DependenciesTestSupport
import Foundation
import Sharing
import SQLiteData
import OrderedCollections
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies { $0.uuid = .incrementing }) struct ContextualPermissionTests {
    @Test
    func getStartedCompletesWelcome() async {
      let store = TestStore(initialState: WelcomeFeature.State()) { WelcomeFeature() }
      await store.send(.getStartedButtonTapped)
      await store.receive(\.delegate)
    }

    @Test
    func welcomePersistsCompletionAndPreservesItAcrossAccessRefresh() async {
      @Dependency(\.defaultAppStorage) var defaults
      defaults.set(false, forKey: "hasCompletedWelcome")
      let store = TestStore(initialState: AppFeature.State()) { AppFeature() }
      #expect(store.state.destination?.welcome != nil)
      await store.send(.proAccessUpdated(.unknown))
      #expect(store.state.destination?.welcome != nil)
      await store.send(.destination(.presented(.welcome(.delegate(.completed))))) {
        $0.$hasCompletedWelcome.withLock { $0 = true }
        $0.destination = nil
      }
      #expect(defaults.bool(forKey: "hasCompletedWelcome"))
      #expect(AppFeature.State().destination == nil)
    }

    @Test(arguments: [SubscriptionEntitlement.free, .pro])
    func accessDoesNotRequestPermissionsOrInterruptWelcome(access: SubscriptionEntitlement) async {
      @Dependency(\.defaultAppStorage) var defaults
      defaults.set(false, forKey: "hasCompletedWelcome")
      let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
        try! clearDatabase($0.defaultDatabase)
        $0.locationClient.requestAuthorization = { Issue.record("Unexpected location request"); return .denied }
        $0.alarmAuthorization.request = { Issue.record("Unexpected alarm request"); return .denied }
      }
      await store.send(.proAccessLoaded(access)) {
        $0.hasLoadedAccess = true
        $0.proAccess = access
      }
      #expect(store.state.destination?.welcome != nil)
      await store.finish()
    }

    @Test
    func welcomeDefersDeepLinkUntilCompletion() async {
      @Dependency(\.defaultAppStorage) var defaults
      defaults.set(false, forKey: "hasCompletedWelcome")
      let url = URL(string: "supershot://game/00000000-0000-0000-0000-000000000003")!
      let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
        $0.gameTimer.reconcile = { _ in throw PermissionTestError.unavailable }
      }
      await store.send(.deepLinkOpened(url)) { $0.pendingDeepLink = url }
      #expect(store.state.games.path.isEmpty)
      await store.send(.destination(.presented(.welcome(.delegate(.completed))))) {
        $0.$hasCompletedWelcome.withLock { $0 = true }
        $0.destination = nil
        $0.pendingDeepLink = nil
      }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.receive(\.deepLinkOpened)
      await store.receive(\.games.gameDeepLinkOpened)
      await store.receive(\.games.resumeGameResponse)
      #expect(store.state.games.alert != nil)
    }

    @Test
    func locationRequiresTapThenLoadsAfterConsent() async {
      let clock = TestClock()
      let status = LockIsolated(LocationAuthorizationStatus.notDetermined)
      let requests = LockIsolated(0)
      let store = TestStore(initialState: NewGameFeature.State()) { NewGameFeature() } withDependencies: {
        $0.locationClient.authorizationStatus = { status.value }
        $0.locationClient.requestAuthorization = {
          requests.withValue { $0 += 1 }
          try? await clock.sleep(for: .seconds(1))
          status.setValue(.authorized)
          return .authorized
        }
        $0.locationClient.currentLocation = { LocationClient.previewLocation }
      }
      await store.send(.task)
      #expect(requests.value == 0)
      await store.send(.locationButtonTapped) { $0.location = .requesting }
      await store.send(.locationButtonTapped)
      await clock.advance(by: .seconds(1))
      await store.receive(\.locationAuthorizationResponse) { $0.location = .loading }
      await store.receive(\.locationResponse) { $0.location = .loaded(LocationClient.previewLocation) }
      #expect(requests.value == 1)
    }

    @Test(arguments: [LocationAuthorizationStatus.denied, .restricted])
    func unavailableLocationNeverRequestsAgain(status: LocationAuthorizationStatus) async {
      let store = TestStore(initialState: NewGameFeature.State()) { NewGameFeature() } withDependencies: {
        $0.locationClient.authorizationStatus = { status }
        $0.locationClient.requestAuthorization = { Issue.record("Unexpected request"); return status }
      }
      await store.send(.task) { $0.location = status == .denied ? .denied : .restricted }
      await store.send(.locationButtonTapped)
      #expect(store.state.gameLocation == nil)
    }

    @Test(arguments: [LocationAuthorizationStatus.denied, .restricted])
    func locationConsentCanBeDeclined(status: LocationAuthorizationStatus) async {
      let store = TestStore(initialState: NewGameFeature.State()) { NewGameFeature() } withDependencies: {
        $0.locationClient.authorizationStatus = { .notDetermined }
        $0.locationClient.requestAuthorization = { status }
        $0.locationClient.currentLocation = { Issue.record("Unexpected location fetch"); throw PermissionTestError.unavailable }
      }
      await store.send(.locationButtonTapped) { $0.location = .requesting }
      await store.receive(\.locationAuthorizationResponse) { $0.location = status == .denied ? .denied : .restricted }
    }

    @Test
    func failedLocationFetchCanRetry() async {
      let store = TestStore(initialState: NewGameFeature.State()) { NewGameFeature() } withDependencies: {
        $0.locationClient.authorizationStatus = { .authorized }
        $0.locationClient.currentLocation = { throw PermissionTestError.unavailable }
      }
      await store.send(.task) { $0.location = .loading }
      await store.receive(\.locationResponse) { $0.location = .failed }
      store.dependencies.locationClient.currentLocation = { LocationClient.previewLocation }
      await store.send(.locationButtonTapped) { $0.location = .loading }
      await store.receive(\.locationResponse) { $0.location = .loaded(LocationClient.previewLocation) }
    }

    @Test
    func locationReloadsWhenSettingsGrantsAccess() async {
      var state = NewGameFeature.State()
      state.location = .denied
      let store = TestStore(initialState: state) { NewGameFeature() } withDependencies: {
        $0.locationClient = .preview
      }
      await store.send(.sceneBecameActive) { $0.location = .loading }
      await store.receive(\.locationResponse) { $0.location = .loaded(LocationClient.previewLocation) }
      await store.send(.sceneBecameActive)
    }

    @Test
    func freeAlarmCardPromotesWithoutRequestingPermission() async {
      var state = AlarmPermissionFeature.State()
      state.access = .free
      let store = TestStore(initialState: state) { AlarmPermissionFeature() } withDependencies: {
        $0.alarmAuthorization.request = { Issue.record("Unexpected request"); return .denied }
      }
      await store.send(.enableButtonTapped)
      await store.receive { if case .delegate(.proPromotionTapped) = $0 { true } else { false } }
    }

    @Test
    func upgradeRefreshDoesNotRequestAlarmAccess() async {
      let store = TestStore(initialState: AlarmPermissionFeature.State()) { AlarmPermissionFeature() } withDependencies: {
        $0.alarmAuthorization.status = { .notDetermined }
        $0.alarmAuthorization.request = { Issue.record("Unexpected request"); return .denied }
      }
      await store.send(.refresh(.free)) { $0.access = .free }
      await store.send(.refresh(.pro)) { $0.access = .pro }
    }

    @Test(arguments: [AlarmAuthorizationStatus.authorized, .denied])
    func alarmConsentHandlesResultAndDuplicateTaps(status: AlarmAuthorizationStatus) async {
      var state = AlarmPermissionFeature.State()
      state.access = .pro
      let clock = TestClock()
      let requests = LockIsolated(0)
      let store = TestStore(initialState: state) { AlarmPermissionFeature() } withDependencies: {
        $0.alarmAuthorization.request = {
          requests.withValue { $0 += 1 }
          try await clock.sleep(for: .seconds(1))
          return status
        }
      }
      await store.send(.enableButtonTapped) { $0.isRequesting = true }
      await store.send(.enableButtonTapped)
      await clock.advance(by: .seconds(1))
      await store.receive(\.authorizationResponse) {
        $0.isRequesting = false
        $0.authorization = status
      }
      if status == .authorized { await store.receive { if case .delegate(.authorized) = $0 { true } else { false } } }
      await store.send(.enableButtonTapped)
      #expect(requests.value == 1)
    }

    @Test
    func alarmRequestFailureCanRetry() async {
      var state = AlarmPermissionFeature.State()
      state.access = .pro
      let store = TestStore(initialState: state) { AlarmPermissionFeature() } withDependencies: {
        $0.alarmAuthorization.request = { throw PermissionTestError.unavailable }
      }
      await store.send(.enableButtonTapped) { $0.isRequesting = true }
      await store.receive(\.authorizationResponse) {
        $0.isRequesting = false
        $0.errorMessage = "Supershot couldn’t request alarm access. Try again."
      }
      store.dependencies.alarmAuthorization.request = { .authorized }
      await store.send(.enableButtonTapped) { $0.isRequesting = true; $0.errorMessage = nil }
      await store.receive(\.authorizationResponse) { $0.isRequesting = false; $0.authorization = .authorized }
      await store.receive { if case .delegate(.authorized) = $0 { true } else { false } }
    }

    @Test
    func returningFromSettingsRecognizesAlarmConsent() async {
      var state = AlarmPermissionFeature.State()
      state.access = .pro
      state.authorization = .denied
      let store = TestStore(initialState: state) { AlarmPermissionFeature() } withDependencies: {
        $0.alarmAuthorization.status = { .authorized }
      }
      await store.send(.refresh(.pro)) { $0.authorization = .authorized }
      await store.receive { if case .delegate(.authorized) = $0 { true } else { false } }
    }

    @Test
    func setupRoutesAlarmPromotionThroughBothTabs() async {
      var setup = NewGameFeature.State()
      setup.alarms.access = .free
      var games = GamesFeature.State()
      games.path.append(.setup(setup))
      let gamesStore = TestStore(initialState: games) { GamesFeature() }
      gamesStore.exhaustivity = .off(showSkippedAssertions: false)
      await gamesStore.send(.path(.element(id: games.path.ids[0], action: .setup(.alarms(.enableButtonTapped)))))
      await gamesStore.receive(\.delegate)
      var teams = TeamsFeature.State()
      teams.path.append(.setup(setup))
      let teamsStore = TestStore(initialState: teams) { TeamsFeature() }
      teamsStore.exhaustivity = .off(showSkippedAssertions: false)
      await teamsStore.send(.path(.element(id: teams.path.ids[0], action: .setup(.alarms(.enableButtonTapped)))))
      await teamsStore.receive(\.delegate)
    }
  }
}

private enum PermissionTestError: Error { case unavailable }
