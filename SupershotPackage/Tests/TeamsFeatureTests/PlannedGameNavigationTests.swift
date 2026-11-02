import ComposableArchitecture
import CustomDump
@testable import Database
import Dependencies
import Foundation
@testable import GameCore
@testable import NewGameFeature
import OrderedCollections
import ScoringFeature
import SQLiteData
@testable import TeamsFeature
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  struct PlannedGameNavigationTests {
    @Test(arguments: [false, true])
    func teamRowAndDeepLinkOpenSummaryAndPreserveTeamDestination(deepLink: Bool) async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let a = Team(id: UUID(101), name: "Ravens")
      let b = Team(id: UUID(102), name: "Swifts")
      var setup = NewGameFeature.State()
      setup.leftTeam.team = a
      setup.rightTeam.team = b
      setup.scheduledAt = Date(timeIntervalSince1970: 20000)
      let draft = try #require(setup.draft)
      let snapshot = try await database.write { db in
        try Team.insert { a; b }.execute(db)
        return try draft.save(db)
      }
      let row = try await database.read { try GamesRequest().fetch($0).games[0] }
      var state = TeamsFeature.State()
      state.path.append(.teamDetail(TeamDetailFeature.State(teamID: a.id)))
      let store = TestStore(initialState: state) { TeamsFeature() }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(deepLink ? .gameDeepLinkOpened(row.id) : .teamGameRowTapped(row))
      await store.receive {
        if case .resumeGameResponse(_, .success) = $0 {
          true
        } else {
          false
        }
      }
      #expect(store.state.newGame == nil)
      guard case let .plannedGame(summary) = store.state.path.last else {
        Issue.record("Expected a planned-game summary")
        return
      }
      expectNoDifference(summary.snapshot, snapshot)
      #expect(store.state.hasGameRoute(for: snapshot.game.id))
      let summaryID = store.state.path.ids[1]
      await store.send(.path(.element(id: summaryID, action: .plannedGame(.startGameButtonTapped))))
      await store.receive {
        if case .path(.element(id: _, action: .plannedGame(.snapshotResponse(.score, .success)))) = $0 {
          true
        } else {
          false
        }
      }
      await store.receive {
        if case .path(.element(id: _, action: .plannedGame(.delegate(.scoringPrepared)))) = $0 {
          true
        } else {
          false
        }
      }
      expectNoDifference(store.state.path.count, 2)
      #expect(store.state.path[0].is(\.teamDetail))
      guard case let .scoring(scoring) = store.state.path.last else {
        Issue.record("Expected scoring above the team destination")
        return
      }
      expectNoDifference(scoring.gameID, snapshot.game.id)
      #expect(scoring.startedAt == nil)
    }
  }
}
