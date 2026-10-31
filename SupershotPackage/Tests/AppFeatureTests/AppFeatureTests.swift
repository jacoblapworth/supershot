@testable import AlarmClient
@testable import AppFeature
@testable import AppSettings
import AppUI
import ComposableArchitecture
import CustomDump
@testable import Database
import Dependencies
import DependenciesTestSupport
import FeatureFlagsClient
import Foundation
@testable import GameAnalysis
@testable import GameCore
@testable import GameDetailFeature
@testable import GameServices
@testable import GamesFeature
import GRDB
@testable import LocationClient
@testable import NewGameFeature
import OrderedCollections
@testable import PaywallFeature
@testable import PermissionsFeature
@testable import PreviewSupport
@testable import ScoringFeature
@testable import SettingsFeature
@testable import SharedModels
@testable import SoundEffectsClient
import SQLiteData
@testable import SubscriptionClient
import SwiftUI
@testable import TeamEditingFeature
@testable import TeamsFeature
import Testing
import TestSupport
@testable import UI
@testable import WidgetSupport
#if os(iOS)
  internal import AlarmKit
#endif

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
    $0.defaultAppStorage.set(true, forKey: "hasCompletedWelcome")
  }) struct AppFeatureTests {
    #if os(macOS)
      @Test func macNavigationDisablesDuringNestedPresentationsAndPendingSaves() {
        var state = AppFeature.State()
        #expect(!state.macHasBlockingPresentation)
        var setup = NewGameFeature.State()
        setup.isSaving = true
        state.games.newGame = setup
        #expect(state.macHasBlockingPresentation)
        state.games.newGame = nil
        var teamDetail = TeamDetailFeature.State(teamID: UUID(1))
        teamDetail.editor = TeamEditorFeature.State(team: Team(id: UUID(1), name: "Ravens"))
        state.teams.path.append(.teamDetail(teamDetail))
        #expect(state.macHasBlockingPresentation)
        state.teams.path.removeAll()
        state.destination = .proPaywall(PaywallFeature.State())
        #expect(state.macHasBlockingPresentation)
      }
    #endif

    @Test
    func failedSubscriptionLookupFallsBackToFree() async {
      let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        try! clearDatabase($0.defaultDatabase)
        $0.proSubscription = SubscriptionClient(
          accessUpdates: { AsyncStream { $0.finish() } },
          currentAccess: { throw SubscriptionTestError.unavailable }
        )
      }

      await store.send(.task) {
        $0.hasStartedSubscriptionObservation = true
      }
      await store.receive {
        guard case .proAccessLoaded(.free) = $0 else { return false }
        return true
      } assert: {
        $0.hasLoadedAccess = true
        $0.proAccess = .free
      }
      await store.finish()
    }

    @Test
    func promotionPresentsPaywallAndProAccessDismissesIt() async {
      var state = AppFeature.State()
      state.hasLoadedAccess = true
      state.proAccess = .free
      let store = TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        try! clearDatabase($0.defaultDatabase)
      }

      await store.send(.proPromotionTapped) {
        $0.destination = .proPaywall(PaywallFeature.State())
      }
      await store.send(.proAccessUpdated(.pro)) {
        $0.proAccess = .pro
        $0.destination = nil
      }
      await store.finish()
    }

    @Test(arguments: [SubscriptionEntitlement.free, .unknown])
    func nonProAccessRetainsPaywallWhenPermissionsAreResolved(
      access: SubscriptionEntitlement
    ) async {
      var state = AppFeature.State()
      state.destination = .proPaywall(PaywallFeature.State())
      state.proAccess = .pro
      let store = TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        try! clearDatabase($0.defaultDatabase)
        $0.locationClient = .preview
      }

      await store.send(.proAccessUpdated(access)) {
        $0.proAccess = access
      }
      await store.finish()
    }

    @Test
    func paywallProAccessDismissesWhenPermissionsAreResolved() async {
      var state = AppFeature.State()
      state.destination = .proPaywall(PaywallFeature.State())
      state.proAccess = .free
      let store = TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        try! clearDatabase($0.defaultDatabase)
      }

      await store.send(.destination(.presented(.proPaywall(.customerInfoUpdated(.pro)))))
      await store.receive {
        guard case .destination(.presented(.proPaywall(.delegate(.accessChanged(.pro))))) = $0
        else { return false }
        return true
      } assert: {
        $0.proAccess = .pro
        $0.destination = nil
      }
      await store.finish()
    }

    @Test
    func dismissingPaywallPreservesEntitlementAndSelectedTab() async {
      var state = AppFeature.State()
      state.destination = .proPaywall(PaywallFeature.State())
      state.proAccess = .free
      state.selectedTab = .settings
      let store = TestStore(initialState: state) {
        AppFeature()
      }

      await store.send(.destination(.dismiss)) {
        $0.destination = nil
      }
    }

    @Test
    func sceneActivationRefreshesAccessAndDismissesPaywall() async {
      var state = AppFeature.State()
      state.destination = .proPaywall(PaywallFeature.State())
      state.hasStartedSubscriptionObservation = true
      state.proAccess = .free
      let store = TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        try! clearDatabase($0.defaultDatabase)
        $0.proSubscription.currentAccess = { .pro }
      }

      await store.send(.sceneBecameActive)
      await store.receive {
        guard case .proAccessUpdated(.pro) = $0 else { return false }
        return true
      } assert: {
        $0.proAccess = .pro
        $0.destination = nil
      }
      await store.finish()
    }

    @Test
    func childDelegatesUpdateGlobalPremiumState() async {
      var state = AppFeature.State()
      state.hasLoadedAccess = true
      state.proAccess = .free
      let store = TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        try! clearDatabase($0.defaultDatabase)
      }

      await store.send(.games(.delegate(.proPromotionTapped)))
      await store.receive {
        guard case .proPromotionTapped = $0 else { return false }
        return true
      } assert: {
        $0.destination = .proPaywall(PaywallFeature.State())
      }
      await store.send(.settings(.delegate(.proAccessChanged(.pro))))
      await store.receive {
        guard case .proAccessUpdated(.pro) = $0 else { return false }
        return true
      } assert: {
        $0.proAccess = .pro
        $0.destination = nil
      }
      await store.finish()
    }

    @Test
    func entitlementTransitionsSynchronizePremiumPresentations() async {
      let seedStore = Self.makeAppScoringStore()
      let database = seedStore.dependencies.defaultDatabase
      let events = LockIsolated<[String]>([])
      var timer = GameTimerClient.live
      timer.refreshActivity = { _ in events.withValue { $0.append("activity") } }
      timer.scheduleAlarm = { _ in events.withValue { $0.append("alarm") }; return false }
      timer.endPresentation = { _ in events.withValue { $0.append("cleanup") } }

      var state = AppFeature.State()
      state.hasLoadedAccess = true
      state.proAccess = .free
      let store = TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        $0.alarmAuthorization = .authorized
        $0.defaultDatabase = database
        $0.gameTimer = timer
      }

      await store.send(.proAccessUpdated(.pro)) {
        $0.proAccess = .pro
      }
      await store.finish()
      expectNoDifference(events.value, ["activity", "alarm"])

      events.setValue([])
      await store.send(.proAccessUpdated(.free)) {
        $0.proAccess = .free
      }
      await store.finish()
      expectNoDifference(events.value, ["cleanup"])
    }

    @Test(arguments: [true, false])
    func reconciliationRespectsIndependentCapabilities(showsActivity: Bool) async throws {
      let seedStore = Self.makeAppScoringStore()
      let database = seedStore.dependencies.defaultDatabase
      let before = try await database.read { try GameSnapshot.fetch($0, gameID: UUID(3)) }
      let events = LockIsolated<[String]>([])
      var timer = GameTimerClient.live
      timer.refreshActivity = { _ in events.withValue { $0.append("activity") } }
      timer.scheduleAlarm = { _ in events.withValue { $0.append("alarm") }; return false }
      timer.endPresentation = { _ in Issue.record("Must not end both capabilities") }
      let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
        $0.defaultDatabase = database
        $0.gameTimer = timer
        $0.featureFlags = FeatureFlagsClient { feature, _ in
          feature == .liveActivities ? showsActivity : !showsActivity
        }
        $0.alarmAuthorization = .authorized
        $0.alarmClient.reconcileAlarms = { ids in
          expectNoDifference(ids, showsActivity ? [] : [UUID(3)])
        }
        $0.alarmClient.reconcileActivities = { ids in
          expectNoDifference(ids, showsActivity ? [UUID(3)] : [])
          events.withValue { $0.append("reconcileActivities") }
        }
        $0.alarmClient.endActivity = { _ in events.withValue { $0.append("endActivity") } }
      }
      await store.send(.proAccessUpdated(.pro)) { $0.proAccess = .pro }
      await store.finish()
      expectNoDifference(
        events.value,
        showsActivity
          ? ["reconcileActivities", "activity"]
          : ["reconcileActivities", "endActivity", "alarm"]
      )
      let after = try await database.read { try GameSnapshot.fetch($0, gameID: UUID(3)) }
      expectNoDifference(after, before)
    }

    @Test func foregroundLookupFailurePreservesAccessAndPresentations() async {
      let events = LockIsolated(0)
      var state = AppFeature.State()
      state.hasStartedSubscriptionObservation = true
      state.proAccess = .pro
      let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
        $0.proSubscription.currentAccess = { throw SubscriptionTestError.unavailable }
        $0.alarmClient.reconcileAlarms = { _ in events.withValue { $0 += 1 } }
      }
      await store.send(.sceneBecameActive)
      await store.finish()
      expectNoDifference(store.state.proAccess, .pro)
      expectNoDifference(events.value, 0)
    }

    @Test func freeAccessReconcilesActivitiesEvenWithoutStoredGames() async throws {
      let reconciliations = LockIsolated<[Set<UUID>]>([])
      let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
        try! clearDatabase($0.defaultDatabase)
        $0.featureFlags = FeatureFlagsClient { _, _ in false }
        $0.alarmClient.reconcileActivities = { ids in
          reconciliations.withValue { $0.append(ids) }
        }
      }
      await store.send(.proAccessUpdated(.free)) { $0.proAccess = .free }
      await store.finish()
      expectNoDifference(reconciliations.value, [[]])
    }

    @Test
    func paywallReportsPurchaseAndRestoreAccess() async {
      let store = TestStore(initialState: PaywallFeature.State()) {
        PaywallFeature()
      }

      await store.send(.customerInfoUpdated(.free))
      await store.receive {
        guard case .delegate(.accessChanged(.free)) = $0 else { return false }
        return true
      }
      await store.send(.customerInfoUpdated(.pro))
      await store.receive {
        guard case .delegate(.accessChanged(.pro)) = $0 else { return false }
        return true
      }
    }

    @Test(arguments: ["supershot", "supershot-dev"])
    func gameDeepLinkReconcilesAndRestoresRunningScoringRoute(scheme: String) async throws {
      var scoring = Self.appScoringState()
      scoring.timerEndsAt = Date(timeIntervalSince1970: 1900)
      let seedStore = Self.makeAppScoringStore(state: scoring)
      let database = seedStore.dependencies.defaultDatabase
      let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.date.now = Date(timeIntervalSince1970: 1100)
        $0.defaultDatabase = database
        $0.gameTimer = .live
      }
      store.exhaustivity = .off(showSkippedAssertions: false)

      try await store.send(
        .deepLinkOpened(#require(URL(string: "\(scheme)://game/\(UUID(3).uuidString)")))
      )
      await store.receive {
        guard case let .games(.resumeGameResponse(request, .success)) = $0 else {
          return false
        }
        return request.gameID == UUID(3)
      }

      expectNoDifference(store.state.games.path.count, 1)
      guard case let .scoring(restored) = store.state.games.path[0] else {
        Issue.record("Expected the running scoring route")
        return
      }
      expectNoDifference(restored.elapsedSeconds, 100)
      expectNoDifference(restored.isTimerRunning, true)
      expectNoDifference(
        restored.timerEndsAt,
        Date(timeIntervalSince1970: 1900)
      )
    }

    @Test
    func tabsRetainIndependentNavigationHistories() async {
      var state = AppFeature.State()
      state.games.newGame = NewGameFeature.State()
      state.teams.path.append(
        .teamDetail(TeamDetailFeature.State(teamID: UUID(1)))
      )
      let store = TestStore(initialState: state) {
        AppFeature()
      }

      await store.send(.selectedTabChanged(.teams)) {
        $0.selectedTab = .teams
      }

      #expect(store.state.games.newGame != nil)
      expectNoDifference(store.state.games.path.count, 0)
      expectNoDifference(store.state.teams.path.count, 1)
    }

    @Test
    func gameDeepLinkSelectsTeamsForAnExistingTeamsScoringRoute() async throws {
      let scoring = Self.appScoringState()
      let seedStore = Self.makeAppScoringStore(state: scoring)
      var state = AppFeature.State()
      state.teams.path.append(.scoring(scoring))
      let store = TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        $0.defaultDatabase = seedStore.dependencies.defaultDatabase
        $0.gameTimer = .live
      }
      store.exhaustivity = .off(showSkippedAssertions: false)

      try await store.send(
        .deepLinkOpened(#require(URL(string: "supershot://game/\(UUID(3).uuidString)")))
      ) {
        $0.selectedTab = .teams
      }

      expectNoDifference(store.state.games.path.count, 0)
      expectNoDifference(store.state.teams.path.count, 1)
    }

    private static func makeAppScoringStore(
      state: ScoringFeature.State = appScoringState(),
      date: Date = Date(timeIntervalSince1970: 1000),
      clock: TestClock<Duration>? = nil,
      dismiss: DismissEffect? = nil,
      gameTimer: GameTimerClient? = nil
    ) -> TestStoreOf<ScoringFeature> {
      let clockStart = clock?.now
      return TestStore(initialState: state) {
        ScoringFeature()
      } withDependencies: {
        if let clock, let clockStart {
          $0.date = DateGenerator {
            let components = clockStart.duration(to: clock.now).components
            let seconds = Double(components.seconds)
              + Double(components.attoseconds) / 1_000_000_000_000_000_000
            return date.addingTimeInterval(seconds)
          }
        } else {
          $0.date.now = date
        }
        $0.uuid = .incrementing
        $0.defaultAppStorage.set(true, forKey: "hasCompletedWelcome")
        try! $0.bootstrapDatabase()
        try! clearDatabase($0.defaultDatabase)
        try! $0.defaultDatabase.write { db in
          try Team.insert {
            Team(id: UUID(1), name: "Ravens")
            Team(id: UUID(2), name: "Swifts")
          }
          .execute(db)

          try Game.insert {
            Game(
              id: UUID(3),
              startedAt: state.startedAt,
              endedAt: nil,
              teamAID: UUID(1),
              teamBID: UUID(2),
              centrePassTeamID: state.centrePassTeamID,
              isAwaitingCentrePassConfirmation: state.isShowingLastCentrePassBanner,
              currentPhaseIndex: state.currentPhaseIndex,
              elapsedSeconds: state.elapsedSeconds,
              timerEndsAt: state.timerEndsAt
            )
          }
          .execute(db)
          try GamePeriod.insert { state.periods }.execute(db)
        }
        if let clock {
          $0.continuousClock = clock
        }
        if let dismiss {
          $0.dismiss = dismiss
        }
        if let gameTimer {
          $0.gameTimer = gameTimer
        }
      }
    }

    private nonisolated static func appScoringState() -> ScoringFeature.State {
      ScoringFeature.State(
        centrePassTeamID: UUID(1),
        gameID: UUID(3),
        periods: testGamePeriods(gameID: UUID(3)),
        startedAt: Date(timeIntervalSince1970: 500),
        teamA: ScoringFeature.Team(
          id: UUID(1),
          bibColor: ColorPalette.blue,
          name: "Ravens"
        ),
        teamB: ScoringFeature.Team(
          id: UUID(2),
          bibColor: ColorPalette.red,
          name: "Swifts"
        )
      )
    }
  }
}

private nonisolated enum SubscriptionTestError: Error {
  case unavailable
}
