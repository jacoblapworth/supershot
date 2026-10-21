import ComposableArchitecture
import CustomDump
@testable import Database
import Dependencies
import Foundation
@testable import GameCore
import GameServices
@testable import GamesFeature
@testable import NewGameFeature
import OrderedCollections
import SQLiteData
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  struct PlannedGameNavigationTests {
    private func setup() throws -> NewGameFeature.State {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let a = Team(id: UUID(101), name: "A")
      let b = Team(id: UUID(102), name: "B")
      try database.write { db in
        try Team.insert {
          a
          b
        }.execute(db)
      }
      var state = NewGameFeature.State()
      state.leftTeam.team = a
      state.rightTeam.team = b
      state.court = "3"
      return state
    }

    @Test(arguments: [false, true])
    func rowAndDeepLinkOpenPlannedSetupWithoutReconciliation(deepLink: Bool) async throws {
      @Dependency(\.defaultDatabase) var database
      let state = try setup()
      let draft = try #require(state.draft)
      try await database.write { db in _ = try draft.save(db) }
      let row = try await database.read { try GamesRequest().fetch($0).games[0] }
      let store = TestStore(initialState: GamesFeature.State()) {
        GamesFeature()
      } withDependencies: {
        $0.gameTimer.reconcile = { _ in
          Issue.record("Planned games must bypass active-game reconciliation")
          throw GameSetupDraft.SaveError.gameAlreadyStarted
        }
      }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(deepLink ? .gameDeepLinkOpened(row.id) : .gameRowTapped(row))
      await store.receive {
        if case .resumeGameResponse(_, .success) = $0 {
          return true
        }
        return false
      }
      guard case let .setup(setup) = store.state.path.last else {
        Issue.record("Expected planned setup")
        return
      }
      expectNoDifference(setup.draft, state.draft)
    }

    @Test func nativePopSavesInParentAfterSetupRouteIsRemoved() async throws {
      @Dependency(\.defaultDatabase) var database
      let setup = try setup()
      var state = GamesFeature.State()
      state.path.append(.setup(setup))
      let store = TestStore(initialState: state) { GamesFeature() }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.path(.popFrom(id: store.state.path.ids[0])))
      await store.finish()
      #expect(store.state.path.isEmpty)
      let gameID = setup.gameID
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: gameID) }
      #expect(snapshot.game.isPlanned)
      expectNoDifference(snapshot.game.court, "3")
    }

    @Test func failedPopSaveRestoresEditorForRetry() async throws {
      @Dependency(\.defaultDatabase) var database
      let setup = try setup()
      let teamID = try #require(setup.leftTeam.team?.id)
      try await database.write { db in try Team.find(teamID).delete().execute(db) }
      var state = GamesFeature.State()
      state.path.append(.setup(setup))
      let store = TestStore(initialState: state) { GamesFeature() }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.path(.popFrom(id: store.state.path.ids[0])))
      await store.receive {
        if case .setupExitSaveFailed = $0 {
          return true
        }
        return false
      }
      guard case let .setup(restored) = store.state.path.last else {
        Issue.record("Expected setup to be restored after save failure")
        return
      }
      expectNoDifference(restored.draft, setup.draft)
      #expect(restored.errorMessage != nil)
    }

    @Test func plansSortAboveHistoryAndAreExcludedFromInProgress() {
      func row(_ id: Int, scheduled: Double? = nil, created: Double? = nil) -> GameListItem {
        GameListItem(
          id: UUID(id), startedAt: nil, teamAName: "A", teamAScore: 0,
          teamBName: "B", teamBScore: 0, createdAt: Date(timeIntervalSince1970: created ?? Double(id)),
          scheduledAt: scheduled.map(Date.init(timeIntervalSince1970:))
        )
      }
      let unscheduled = row(1)
      let newerUnscheduled = row(2)
      let later = row(3, scheduled: 2000)
      let sooner = row(4, scheduled: 1000)
      let sameTime = row(6, scheduled: 1000, created: 0)
      let active = GameListItem(
        id: UUID(5), startedAt: Date(), teamAName: "A", teamAScore: 0,
        teamBName: "B", teamBScore: 0
      )
      let rows = [unscheduled, active, later, newerUnscheduled, sooner, sameTime]
      expectNoDifference(
        GamesFilter.all.games(from: rows).map(\.id), [UUID(6), UUID(4), UUID(3), UUID(2), UUID(1), UUID(5)]
      )
      expectNoDifference(
        GamesFilter.planned.games(from: rows).map(\.id), [UUID(6), UUID(4), UUID(3), UUID(2), UUID(1)]
      )
      expectNoDifference(GamesFilter.inProgress.games(from: rows), [active])
    }
  }
}
