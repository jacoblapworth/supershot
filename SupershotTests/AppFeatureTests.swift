import SwiftUI
import ComposableArchitecture
import CustomDump
import Dependencies
import Foundation
import GRDB
import OrderedCollections
import SQLiteData
import Testing

@testable import Supershot
internal import AlarmKit
import DependenciesTestSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
  }) struct AppFeatureTests {
    @Test
    func failedSubscriptionLookupFallsBackToFree() async {
      let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        try! clearDatabase($0.defaultDatabase)
        $0.proSubscription = ProSubscriptionClient(
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
        $0.hasCheckedPermissions = true
        $0.proAccess = .free
      }
      await store.finish()
    }

    @Test
    func promotionPresentsPaywallAndProAccessDismissesIt() async {
      var state = AppFeature.State()
      state.hasCheckedPermissions = true
      state.proAccess = .free
      let store = TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        try! clearDatabase($0.defaultDatabase)
      }

      await store.send(.proPromotionTapped) {
        $0.proPaywall = ProPaywallFeature.State()
      }
      await store.send(.proAccessUpdated(.pro)) {
        $0.proAccess = .pro
        $0.proPaywall = nil
      }
      await store.finish()
    }

    @Test
    func childDelegatesUpdateGlobalPremiumState() async {
      var state = AppFeature.State()
      state.hasCheckedPermissions = true
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
        $0.proPaywall = ProPaywallFeature.State()
      }
      await store.send(.settings(.delegate(.proAccessChanged(.pro))))
      await store.receive {
        guard case .proAccessUpdated(.pro) = $0 else { return false }
        return true
      } assert: {
        $0.proAccess = .pro
        $0.proPaywall = nil
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
      timer.scheduleAlarm = { _ in events.withValue { $0.append("alarm") } }
      timer.endPresentation = { _ in events.withValue { $0.append("cleanup") } }

      var state = AppFeature.State()
      state.hasCheckedPermissions = true
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

    @Test
    func paywallReportsPurchaseAndRestoreAccess() async {
      let store = TestStore(initialState: ProPaywallFeature.State()) {
        ProPaywallFeature()
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

    @Test
    func gameDeepLinkReconcilesAndRestoresRunningScoringRoute() async {
      var scoring = Self.appScoringState()
      scoring.timerEndsAt = Date(timeIntervalSince1970: 1_900)
      let seedStore = Self.makeAppScoringStore(state: scoring)
      let database = seedStore.dependencies.defaultDatabase
      let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.date.now = Date(timeIntervalSince1970: 1_100)
        $0.defaultDatabase = database
        $0.gameTimer = .live
      }
      store.exhaustivity = .off(showSkippedAssertions: false)

      await store.send(
        .deepLinkOpened(URL(string: "supershot://game/\(UUID(3).uuidString)")!)
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
        Date(timeIntervalSince1970: 1_900)
      )
    }

    @Test
    func tabsRetainIndependentNavigationHistories() async {
      var state = AppFeature.State()
      state.games.path.append(.setup(NewGameFeature.State()))
      state.teams.path.append(
        .teamDetail(TeamDetailFeature.State(teamID: UUID(1)))
      )
      let store = TestStore(initialState: state) {
        AppFeature()
      }

      await store.send(.selectedTabChanged(.teams)) {
        $0.selectedTab = .teams
      }

      expectNoDifference(store.state.games.path.count, 1)
      expectNoDifference(store.state.teams.path.count, 1)
    }

    @Test
    func gameDeepLinkSelectsTeamsForAnExistingTeamsScoringRoute() async {
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

      await store.send(
        .deepLinkOpened(URL(string: "supershot://game/\(UUID(3).uuidString)")!)
      ) {
        $0.selectedTab = .teams
      }

      expectNoDifference(store.state.games.path.count, 0)
      expectNoDifference(store.state.teams.path.count, 1)
    }

    private static func makeAppScoringStore(
        state: ScoringFeature.State = appScoringState(),
        date: Date = Date(timeIntervalSince1970: 1_000),
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
