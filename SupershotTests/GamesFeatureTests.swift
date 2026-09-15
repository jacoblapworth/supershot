import SwiftUI
import ComposableArchitecture
import CustomDump
import DependenciesTestSupport
import Foundation
import GRDB
import OrderedCollections
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
  }) struct GamesFeatureTests {
    @Test
    func completedGameOpensDetail() async {
      let game = GameListItem(
        endedAt: Date(timeIntervalSince1970: 2_000),
        id: UUID(3),
        startedAt: Date(timeIntervalSince1970: 1_000),
        teamAName: "Ravens",
        teamAScore: 12,
        teamBName: "Swifts",
        teamBScore: 10
      )
      let store = TestStore(initialState: GamesFeature.State()) {
        GamesFeature()
      }

      await store.send(.gameRowTapped(game)) {
        $0.path.append(
          .gameDetail(GameDetailFeature.State(gameID: game.id))
        )
      }
    }

    @Test
    func newGameOpensSetup() async {
      let store = TestStore(initialState: GamesFeature.State()) {
        GamesFeature()
      }

      await store.send(.newGameButtonTapped) {
        $0.path.append(.setup(NewGameFeature.State()))
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

      await store.send(
        .resumeGameResponse(
          GamesFeature.PendingGameResume(
            gameID: UUID(3),
            requestID: UUID(0)
          ),
          .failure(TabFeatureTestError.unavailable)
        )
      )
      await store.send(
        .resumeGameResponse(request, .failure(TabFeatureTestError.unavailable))
      ) {
        $0.alert = .gameUnavailable
        $0.pendingGameResume = nil
      }
    }

    @Test
    func finishingGameReplacesScoringWithDetailRoute() async {
      var state = GamesFeature.State()
      state.path.append(.scoring(Self.scoringState()))
      let scoringID = state.path.ids[0]
      let store = TestStore(initialState: state) {
        GamesFeature()
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
        (
          try Game.find(UUID(3)).fetchOne(db),
          try Goal.where { $0.gameID.eq(UUID(3)) }.fetchAll(db),
          try Team.fetchAll(db)
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

    private nonisolated static func scoringState() -> ScoringFeature.State {
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
          createdAt: Date(timeIntervalSince1970: 1_000)
        )
      }
      .execute(db)
    }
  }
}

nonisolated enum TabFeatureTestError: Error {
  case unavailable
}
