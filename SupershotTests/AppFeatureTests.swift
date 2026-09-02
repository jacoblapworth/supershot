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
    func finishingGameReplacesScoringWithDetailRoute() async {
      var state = AppFeature.State()
      state.path.append(.scoring(Self.appScoringState()))
      let scoringID = state.path.ids[0]
      let store = TestStore(initialState: state) {
        AppFeature()
      }
      store.exhaustivity = .off(showSkippedAssertions: false)

      await store.send(
        .path(
          .element(
            id: scoringID,
            action: .scoring(.delegate(.gameFinished(UUID(3))))
          )
        )
      )

      expectNoDifference(store.state.path.count, 1)
      guard case let .gameDetail(detail) = store.state.path[0] else {
        Issue.record("Expected the completed game detail route")
        return
      }
      expectNoDifference(detail.gameID, UUID(3))
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
        guard case .resumeGameResponse(UUID(3), .success) = $0 else { return false }
        return true
      }

      expectNoDifference(store.state.path.count, 1)
      guard case let .scoring(restored) = store.state.path[0] else {
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
      state.path.append(.setup(NewGameFeature.State()))
      state.teamsPath.append(
        .teamDetail(TeamDetailFeature.State(teamID: UUID(1)))
      )
      let store = TestStore(initialState: state) {
        AppFeature()
      }

      await store.send(.selectedTabChanged(.teams)) {
        $0.selectedTab = .teams
      }

      expectNoDifference(store.state.path.count, 1)
      expectNoDifference(store.state.teamsPath.count, 1)
    }

    @Test
    func completedTeamGameOpensDetailInTeamsStack() async {
      let game = GameListItem(
        endedAt: Date(timeIntervalSince1970: 2_000),
        id: UUID(3),
        startedAt: Date(timeIntervalSince1970: 1_000),
        teamAName: "Ravens",
        teamAScore: 12,
        teamBName: "Swifts",
        teamBScore: 10
      )
      var state = AppFeature.State()
      state.selectedTab = .teams
      state.teamsPath.append(
        .teamDetail(TeamDetailFeature.State(teamID: UUID(1)))
      )
      let store = TestStore(initialState: state) {
        AppFeature()
      }

      await store.send(.teamGameRowTapped(game)) {
        $0.teamsPath.append(
          .gameDetail(GameDetailFeature.State(gameID: game.id))
        )
      }

      expectNoDifference(store.state.path.count, 0)
      expectNoDifference(store.state.teamsPath.count, 2)
    }

    @Test
    func unfinishedTeamGameResumesAndFinishesInTeamsStack() async {
      let seedStore = Self.makeAppScoringStore()
      let database = seedStore.dependencies.defaultDatabase
      let game = GameListItem(
        endedAt: nil,
        id: UUID(3),
        startedAt: Date(timeIntervalSince1970: 500),
        teamAName: "Ravens",
        teamAScore: 0,
        teamBName: "Swifts",
        teamBScore: 0
      )
      var state = AppFeature.State()
      state.selectedTab = .teams
      state.teamsPath.append(
        .teamDetail(TeamDetailFeature.State(teamID: UUID(1)))
      )
      let store = TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        $0.date.now = Date(timeIntervalSince1970: 1_100)
        $0.defaultDatabase = database
        $0.gameTimer = .live
      }
      store.exhaustivity = .off(showSkippedAssertions: false)

      await store.send(.teamGameRowTapped(game)) {
        $0.loadingGameID = game.id
        $0.loadingGameTab = .teams
      }
      await store.receive {
        guard case .resumeGameResponse(game.id, .success) = $0 else { return false }
        return true
      }

      expectNoDifference(store.state.loadingGameID, nil)
      expectNoDifference(store.state.loadingGameTab, nil)
      expectNoDifference(store.state.path.count, 0)
      expectNoDifference(store.state.teamsPath.count, 2)
      guard case let .scoring(scoring) = store.state.teamsPath[1] else {
        Issue.record("Expected scoring to resume in the Teams stack")
        return
      }
      expectNoDifference(scoring.gameID, game.id)

      let scoringID = store.state.teamsPath.ids[1]
      await store.send(
        .teamsPath(
          .element(
            id: scoringID,
            action: .scoring(.delegate(.gameFinished(game.id)))
          )
        )
      )

      expectNoDifference(store.state.path.count, 0)
      expectNoDifference(store.state.teamsPath.count, 2)
      guard case let .gameDetail(detail) = store.state.teamsPath[1] else {
        Issue.record("Expected scoring to finish in the Teams stack")
        return
      }
      expectNoDifference(detail.gameID, game.id)
    }

    @Test
    func gameDeepLinkSelectsTeamsForAnExistingTeamsScoringRoute() async {
      let scoring = Self.appScoringState()
      let seedStore = Self.makeAppScoringStore(state: scoring)
      var state = AppFeature.State()
      state.teamsPath.append(.scoring(scoring))
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

      expectNoDifference(store.state.path.count, 0)
      expectNoDifference(store.state.teamsPath.count, 1)
    }

    @Test
    func deletingGameRemovesGoalsRetainsTeamsAndEndsPresentation() async throws {
      let seedStore = Self.makeAppScoringStore()
      let database = seedStore.dependencies.defaultDatabase
      let events = LockIsolated<[TimerSystemEvent]>([])
      try await database.write { db in
        try Goal.insert {
          Goal(
            id: UUID(4),
            gameID: UUID(3),
            gamePeriodID: testGamePeriodID(gameID: UUID(3), position: 0),
            teamID: UUID(1),
            elapsedSeconds: 10,
            points: 1,
            createdAt: Date(timeIntervalSince1970: 1_000)
          )
        }
        .execute(db)
      }

      let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.defaultDatabase = database
        $0.alarmClient = Self.timerSystemClient(events: events)
      }

      await store.send(.deleteGameButtonTapped(UUID(3))) {
        $0.deletingGameID = UUID(3)
      }
      await store.receive {
        guard case let .deleteGameResponse(gameID, .success) = $0 else {
          return false
        }
        return gameID == UUID(3)
      } assert: {
        $0.deletingGameID = nil
      }

      let values = try await database.read { db in
        (
          try Game.find(UUID(3)).fetchOne(db),
          try Goal.where { $0.gameID.eq(UUID(3)) }.fetchAll(db),
          try Team.fetchAll(db)
        )
      }
      expectNoDifference(values.0, nil)
      expectNoDifference(values.1, [])
      expectNoDifference(values.2.count, 2)
      expectNoDifference(events.value, [.cancelAlarm, .endActivity])
    }

    @Test
    func deletingTeamRemovesItsGamesAndGoalsAndEndsPresentations() async throws {
      let seedStore = Self.makeAppScoringStore()
      let database = seedStore.dependencies.defaultDatabase
      let events = LockIsolated<[TimerSystemEvent]>([])
      try await database.write { db in
        try Goal.insert {
          Goal(
            id: UUID(4),
            gameID: UUID(3),
            gamePeriodID: testGamePeriodID(gameID: UUID(3), position: 0),
            teamID: UUID(1),
            elapsedSeconds: 10,
            points: 1,
            createdAt: Date(timeIntervalSince1970: 1_000)
          )
        }
        .execute(db)
      }

      let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.defaultDatabase = database
      }

      await store.send(.deleteTeamButtonTapped(UUID(1))) {
        $0.deletingTeamID = UUID(1)
      }
      await store.receive {
        guard case let .deleteTeamResponse(teamID, .success) = $0 else {
          return false
        }
        return teamID == UUID(1)
      } assert: {
        $0.deletingTeamID = nil
      }

      let values = try await database.read { db in
        (
          try Team.find(UUID(1)).fetchOne(db),
          try Game.find(UUID(3)).fetchOne(db),
          try Goal.where { $0.gameID.eq(UUID(3)) }.fetchAll(db),
          try Team.find(UUID(2)).fetchOne(db)
        )
      }
      expectNoDifference(values.0, nil)
      expectNoDifference(values.1, nil)
      expectNoDifference(values.2, [])
      expectNoDifference(values.3?.name, "Swifts")
      expectNoDifference(events.value, [.cancelAlarm, .endActivity])
    }

    private nonisolated static func timerSystemClient(
        events: LockIsolated<[TimerSystemEvent]>,
        alarmUnavailable: Bool = false
      ) -> AlarmClient {
        AlarmClient(
          authorise: { .authorized },
          scheduleAlarm: { snapshot, requestsAuthorization in
            events.withValue {
              $0.append(
                .alarm(
                  snapshot.game.timerEndsAt,
                  requestsAuthorization: requestsAuthorization
                )
              )
            }
            return alarmUnavailable
          },
          updateActivity: { snapshot, _ in
            events.withValue {
              $0.append(.activity(snapshot.game.timerEndsAt))
            }
          },
          cancelAlarm: { _, _ in
            events.withValue { $0.append(.cancelAlarm) }
          },
          endActivity: { _ in
            events.withValue { $0.append(.endActivity) }
          }
        )
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
            bibColorHex: TeamColorPalette.blue,
            name: "Ravens"
          ),
          teamB: ScoringFeature.Team(
            id: UUID(2),
            bibColorHex: TeamColorPalette.red,
            name: "Swifts"
          )
        )
      }
  }
}

private nonisolated enum TimerSystemEvent: Equatable, Sendable {
  case activity(Date?)
  case alarm(Date?, requestsAuthorization: Bool)
  case cancelAlarm
  case endActivity
}

private nonisolated enum SubscriptionTestError: Error {
  case unavailable
}
