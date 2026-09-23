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
  }) struct TeamsFeatureTests {
    @Test
    func completedTeamGameOpensDetail() async {
      let game = GameListItem(
        endedAt: Date(timeIntervalSince1970: 2_000),
        id: UUID(3),
        startedAt: Date(timeIntervalSince1970: 1_000),
        teamAName: "Ravens",
        teamAScore: 12,
        teamBName: "Swifts",
        teamBScore: 10
      )
      let store = TestStore(initialState: TeamsFeature.State()) {
        TeamsFeature()
      }

      await store.send(.teamGameRowTapped(game)) {
        $0.path.append(
          .gameDetail(GameDetailFeature.State(gameID: game.id))
        )
      }
    }

    @Test
    func teamSelectionAndCreationStayWithinTeamsTab() async {
      let team = TeamListItem(
        color: ColorPalette.blue,
        gameCount: 2,
        id: UUID(1),
        name: "Ravens"
      )
      let store = TestStore(initialState: TeamsFeature.State()) {
        TeamsFeature()
      }

      await store.send(.teamRowTapped(team)) {
        $0.path.append(
          .teamDetail(TeamDetailFeature.State(teamID: team.id))
        )
      }
      await store.send(.newTeamButtonTapped) {
        $0.teamEditor = TeamEditorFeature.State()
      }
    }

    @Test
    func unfinishedTeamGameResumesAndFinishesInTeamsStack() async {
      let game = GameListItem(
        endedAt: nil,
        id: UUID(3),
        startedAt: Date(timeIntervalSince1970: 500),
        teamAName: "Ravens",
        teamAScore: 0,
        teamBName: "Swifts",
        teamBScore: 0
      )
      var state = TeamsFeature.State()
      state.path.append(
        .teamDetail(TeamDetailFeature.State(teamID: UUID(1)))
      )
      let store = Self.makeStore(state: state)
      store.exhaustivity = .off(showSkippedAssertions: false)

      await store.send(.teamGameRowTapped(game)) {
        $0.pendingGameResume = TeamsFeature.PendingGameResume(
          gameID: game.id,
          requestID: UUID(0)
        )
      }
      await store.receive {
        guard case let .resumeGameResponse(request, .success) = $0 else {
          return false
        }
        return request.gameID == game.id
      }

      expectNoDifference(store.state.pendingGameResume, nil)
      expectNoDifference(store.state.path.count, 2)
      guard case let .scoring(scoring) = store.state.path[1] else {
        Issue.record("Expected scoring to resume in the Teams stack")
        return
      }
      expectNoDifference(scoring.gameID, game.id)

      let scoringID = store.state.path.ids[1]
      await store.send(
        .path(
          .element(
            id: scoringID,
            action: .scoring(.delegate(.gameFinished(game.id)))
          )
        )
      )

      expectNoDifference(store.state.path.count, 2)
      guard case let .gameDetail(detail) = store.state.path[1] else {
        Issue.record("Expected scoring to finish in the Teams stack")
        return
      }
      expectNoDifference(detail.gameID, game.id)
    }

    @Test
    func staleResumeResponseIsIgnored() async {
      let currentRequest = TeamsFeature.PendingGameResume(
        gameID: UUID(3),
        requestID: UUID(2)
      )
      var state = TeamsFeature.State()
      state.pendingGameResume = currentRequest
      let store = TestStore(initialState: state) {
        TeamsFeature()
      }
      let staleRequest = TeamsFeature.PendingGameResume(
        gameID: UUID(3),
        requestID: UUID(1)
      )

      await store.send(
        .resumeGameResponse(
          staleRequest,
          .failure(TabFeatureTestError.unavailable)
        )
      )
    }

    @Test
    func deletingTeamCascadesGamesAndGoalsAndEndsPresentations() async throws {
      let endedGameIDs = LockIsolated<[Game.ID]>([])
      var gameTimer = GameTimerClient.live
      gameTimer.endPresentation = { gameID in
        endedGameIDs.withValue { $0.append(gameID) }
      }
      let store = Self.makeStore(gameTimer: gameTimer)
      let database = store.dependencies.defaultDatabase

      await store.send(.deleteTeamButtonTapped(UUID(1)))
      await store.finish()

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
      expectNoDifference(endedGameIDs.value, [UUID(3)])
    }

    @Test
    func promotionDelegatesToApp() async {
      let store = TestStore(initialState: TeamsFeature.State()) {
        TeamsFeature()
      }

      await store.send(.proPromotionTapped)
      await store.receive {
        guard case .delegate(.proPromotionTapped) = $0 else { return false }
        return true
      }
    }

    private static func makeStore(
      state: TeamsFeature.State? = nil,
      gameTimer: GameTimerClient = .live
    ) -> TestStoreOf<TeamsFeature> {
      TestStore(initialState: state ?? TeamsFeature.State()) {
        TeamsFeature()
      } withDependencies: {
        $0.date.now = Date(timeIntervalSince1970: 1_100)
        $0.uuid = .incrementing
        try! clearDatabase($0.defaultDatabase)
        try! $0.defaultDatabase.write { db in
          try Self.seedGameAndGoal(db)
        }
        $0.gameTimer = gameTimer
      }
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
