@testable import AlarmClient
@testable import AppSettings
import AppUI
import ComposableArchitecture
import CustomDump
@testable import Database
import DependenciesTestSupport
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
@testable import SharedModels
@testable import SoundEffectsClient
import SQLiteData
@testable import SubscriptionClient
import SwiftUI
@testable import TeamEditingFeature
import Testing
import TestSupport
@testable import UI
@testable import WidgetSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
  }) struct GamesFeatureTests {
    @Test
    func filterSelectionSurvivesSetupNavigation() async {
      let store = TestStore(initialState: GamesFeature.State()) {
        GamesFeature()
      }
      expectNoDifference(store.state.filter, .all)

      await store.send(.filterButtonTapped(.completed)) {
        $0.filter = .completed
      }
      await store.send(.newGameButtonTapped) {
        $0.newGame = withDependencies { $0.uuid = .incrementing } operation: { NewGameFeature.State() }
      }
      await store.send(.newGame(.dismiss)) {
        $0.newGame = nil
      }
      expectNoDifference(store.state.filter, .completed)
      await store.send(.filterButtonTapped(.all)) {
        $0.filter = .all
      }
    }

    @Test
    func filtersPreserveRowsAndOrdering() {
      let completed = GameListItem.previewCompleted
      let unfinished = GameListItem.previewInProgress
      let otherCompleted = GameListItem(
        endedAt: completed.endedAt,
        id: UUID(4),
        startedAt: completed.startedAt,
        teamAName: "Foxes",
        teamAScore: 20,
        teamBName: "Owls",
        teamBScore: 18
      )
      let games = [unfinished, completed, otherCompleted]

      expectNoDifference(GamesFilter.all.games(from: games), games)
      expectNoDifference(GamesFilter.inProgress.games(from: games), [unfinished])
      expectNoDifference(GamesFilter.completed.games(from: games), [completed, otherCompleted])
      for filter in GamesFilter.allCases {
        expectNoDifference(filter.games(from: []), [])
      }
      expectNoDifference(GamesFilter.completed.games(from: [unfinished]), [])
      expectNoDifference(GamesFilter.inProgress.games(from: [completed]), [])
    }

    @Test
    func unfinishedGamesStayInProgressUntilPersistedFinish() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      try await database.write { db in
        try Self.seedGameAndGoal(db)
        for position in 0 ..< 3 {
          try GamePeriod.find(testGamePeriodID(gameID: UUID(3), position: position)).update {
            $0.breakAfterDurationSeconds = #bind(60)
          }.execute(db)
        }
      }

      // Paused play, a break, and final-period confirmation all remain unfinished.
      for phaseIndex in [0, 1, 6] {
        try await database.write { db in
          try Game.find(UUID(3)).update {
            $0.currentPhaseIndex = #bind(phaseIndex)
            $0.elapsedSeconds = #bind(phaseIndex == 6 ? 900 : 0)
            $0.timerEndsAt = #bind(nil as Date?)
          }.execute(db)
        }
        let games = try await database.read { try GamesRequest().fetch($0).games }
        expectNoDifference(GamesFilter.inProgress.games(from: games).map(\.id), [UUID(3)])
        expectNoDifference(GamesFilter.completed.games(from: games), [])
      }

      try await database.write { db in
        try Game.find(UUID(3)).update {
          $0.endedAt = #bind(Date(timeIntervalSince1970: 2000))
        }.execute(db)
      }
      let finishedGames = try await database.read { try GamesRequest().fetch($0).games }
      expectNoDifference(GamesFilter.inProgress.games(from: finishedGames), [])
      expectNoDifference(GamesFilter.completed.games(from: finishedGames).map(\.id), [UUID(3)])
      try await database.write { db in
        try Game.find(UUID(3)).delete().execute(db)
      }
      let remainingGames = try await database.read { try GamesRequest().fetch($0).games }
      expectNoDifference(GamesFilter.completed.games(from: remainingGames), [])
    }

    @Test
    func completedGameOpensDetail() async {
      let game = GameListItem(
        endedAt: Date(timeIntervalSince1970: 2000),
        id: UUID(3),
        startedAt: Date(timeIntervalSince1970: 1000),
        teamAName: "Ravens",
        teamAScore: 12,
        teamBName: "Swifts",
        teamBScore: 10
      )
      let store = TestStore(initialState: GamesFeature.State()) {
        GamesFeature()
      }

      await store.send(.gameRowTapped(game)) {
        $0.path.append(.gameDetail(GameDetailFeature.State(gameID: game.id)))
      }
    }

    @Test
    func newGameOpensSetup() async {
      let store = TestStore(initialState: GamesFeature.State()) {
        GamesFeature()
      }

      await store.send(.newGameButtonTapped) {
        $0.newGame = withDependencies { $0.uuid = .incrementing } operation: { NewGameFeature.State() }
      }
    }

    @Test
    func failedCurrentResumeShowsAlertAndStaleResponseIsIgnored() async {
      let request = GamesFeature.PendingGameResume(
        gameID: UUID(3),
        requestID: UUID(1)
      )
      var state = GamesFeature.State()
      state.pendingGameResume = request
      let store = TestStore(initialState: state) {
        GamesFeature()
      }

      await store.send(.resumeGameResponse(
        GamesFeature.PendingGameResume(
          gameID: UUID(3),
          requestID: UUID(0)
        ),
        .failure(TabFeatureTestError.unavailable)
      ))
      await store.send(.resumeGameResponse(request, .failure(TabFeatureTestError.unavailable))) {
        $0.alert = .gameUnavailable
        $0.pendingGameResume = nil
      }
    }

    @Test
    func finishingGameReplacesScoringWithDetailRoute() async {
      var state = GamesFeature.State()
      state.filter = .inProgress
      state.path.append(.scoring(Self.scoringState()))
      let scoringID = state.path.ids[0]
      let store = TestStore(initialState: state) {
        GamesFeature()
      }
      store.exhaustivity = .off(showSkippedAssertions: false)

      await store.send(.path(.element(
        id: scoringID,
        action: .scoring(.delegate(.gameFinished(UUID(3))))
      )))

      expectNoDifference(store.state.path.count, 1)
      guard case let .gameDetail(detail) = store.state.path[0] else {
        Issue.record("Expected the completed game detail route")
        return
      }
      expectNoDifference(detail.gameID, UUID(3))
      expectNoDifference(store.state.filter, .inProgress)
    }

    @Test
    func deletingGameCascadesGoalsAndEndsItsPresentation() async throws {
      let endedGameIDs = LockIsolated<[Game.ID]>([])
      var gameTimer = GameTimerClient.live
      gameTimer.endPresentation = { gameID in
        endedGameIDs.withValue { $0.append(gameID) }
      }
      let store = TestStore(initialState: GamesFeature.State()) {
        GamesFeature()
      } withDependencies: {
        try! clearDatabase($0.defaultDatabase)
        try! $0.defaultDatabase.write { db in
          try Self.seedGameAndGoal(db)
        }
        $0.gameTimer = gameTimer
      }
      let database = store.dependencies.defaultDatabase

      await store.send(.deleteGameButtonTapped(UUID(3)))
      await store.finish()

      let values = try await database.read { db in
        try (
          Game.find(UUID(3)).fetchOne(db),
          Goal.where { $0.gameID.eq(UUID(3)) }.fetchAll(db),
          Team.fetchAll(db)
        )
      }
      expectNoDifference(values.0, nil)
      expectNoDifference(values.1, [])
      expectNoDifference(values.2.count, 2)
      expectNoDifference(endedGameIDs.value, [UUID(3)])
    }

    @Test
    func promotionDelegatesToApp() async {
      let store = TestStore(initialState: GamesFeature.State()) {
        GamesFeature()
      }

      await store.send(.proPromotionTapped)
      await store.receive {
        guard case .delegate(.proPromotionTapped) = $0 else { return false }
        return true
      }
    }

    @MainActor private static func scoringState() -> ScoringFeature.State {
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

    private nonisolated static func seedGameAndGoal(_ db: Database) throws {
      try Team.insert {
        Team(id: UUID(1), name: "Ravens")
        Team(id: UUID(2), name: "Swifts")
      }
      .execute(db)
      try Game.insert {
        Game(
          id: UUID(3),
          startedAt: Date(timeIntervalSince1970: 500),
          endedAt: nil,
          teamAID: UUID(1),
          teamBID: UUID(2),
          centrePassTeamID: UUID(1),
          isAwaitingCentrePassConfirmation: false,
          currentPhaseIndex: 0,
          elapsedSeconds: 0,
          timerEndsAt: nil
        )
      }
      .execute(db)
      try GamePeriod.insert { testGamePeriods(gameID: UUID(3)) }.execute(db)
      try Goal.insert {
        Goal(
          id: UUID(4),
          gameID: UUID(3),
          gamePeriodID: testGamePeriodID(gameID: UUID(3), position: 0),
          teamID: UUID(1),
          elapsedSeconds: 10,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1000)
        )
      }
      .execute(db)
    }
  }
}
