import AlarmClient
import ComposableArchitecture
import CustomDump
@testable import Database
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import GameCore
@testable import NewGameFeature
import ScoringFeature
import SharedModels
import SQLiteData
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies { $0.alarmAuthorization.status = { .denied } })
  struct PlannedGameSummaryTests {
    private func savedGame(scheduledAt: Date? = nil) throws -> GameSnapshot {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let a = Team(id: UUID(101), name: "Ravens")
      let b = Team(id: UUID(102), name: "Swifts")
      var setup = NewGameFeature.State()
      setup.leftTeam.team = a
      setup.rightTeam.team = b
      setup.scheduledAt = scheduledAt
      setup.court = "3"
      setup.division = "Social"
      setup.selectedLocation = .init(latitude: 1, longitude: 2, pointOfInterestName: "Arena")
      let draft = try #require(setup.draft)
      return try database.write { db in
        try Team.insert { a; b }.execute(db)
        return try draft.save(db)
      }
    }

    @Test(arguments: [nil, -1000.0, 30000.0] as [Double?])
    func startUsesLatestSavedSetupWithoutStartingClockOrDuplicatingGame(time: Double?) async throws {
      @Dependency(\.defaultDatabase) var database
      let snapshot = try savedGame(scheduledAt: time.map(Date.init(timeIntervalSince1970:)))
      try await database.write { db in
        try Game.find(snapshot.game.id).update { $0.court = #bind("4") }.execute(db)
      }
      let store = TestStore(initialState: PlannedGameFeature.State(snapshot: snapshot)) { PlannedGameFeature() }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.startGameButtonTapped)
      await store.receive {
        if case .snapshotResponse(.score, .success) = $0 {
          true
        } else {
          false
        }
      }
      await store.receive { action in
        guard case let .delegate(.scoringPrepared(scoring)) = action else { return false }
        expectNoDifference(scoring.gameID, snapshot.game.id)
        #expect(scoring.startedAt == nil)
        expectNoDifference(scoring.court, "4")
        expectNoDifference(scoring.periods, snapshot.periods)
        expectNoDifference(scoring.teamA.name, snapshot.teamA.name)
        expectNoDifference(scoring.teamB.name, snapshot.teamB.name)
        expectNoDifference(scoring.centrePassTeamID, snapshot.game.centrePassTeamID)
        return true
      }
      await store.send(.startGameButtonTapped)
      await store.finish()
      expectNoDifference(store.state.snapshot?.game.court, "4")
      let saved = try await database.read { try GameSnapshot.fetch($0, gameID: snapshot.game.id) }
      #expect(saved.game.isPlanned)
      #expect(saved.game.timerEndsAt == nil)
      expectNoDifference(saved.game.scheduledAt, snapshot.game.scheduledAt)
      expectNoDifference(saved.game.location, snapshot.game.location)
      expectNoDifference(saved.periods, snapshot.periods)
      let savedCount = try await database.read { try Game.fetchCount($0) }
      expectNoDifference(savedCount, 1)
    }

    @Test(arguments: [false, true])
    func editReturnsToUpdatedSummary(dismiss: Bool) async throws {
      @Dependency(\.defaultDatabase) var database
      let snapshot = try savedGame()
      let store = TestStore(initialState: PlannedGameFeature.State(snapshot: snapshot)) { PlannedGameFeature() }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.editButtonTapped)
      await store.receive {
        if case .snapshotResponse(.edit, .success) = $0 {
          true
        } else {
          false
        }
      }
      expectNoDifference(store.state.editor?.gameID, snapshot.game.id)
      await store.send(.editor(.presented(.binding(.allCasePaths.court.embed("7")))))
      await store.send(dismiss ? .editor(.dismiss) : .editor(.presented(.saveGameButtonTapped)))
      await store.receive { action in
        if dismiss, case .editorDismissalSaved(.success, _) = action {
          return true
        }
        if !dismiss, case .snapshotResponse(.refresh, .success) = action {
          return true
        }
        return false
      }
      await store.finish()
      #expect(store.state.editor == nil)
      expectNoDifference(store.state.snapshot?.game.court, "7")
      let savedCount = try await database.read { try Game.fetchCount($0) }
      expectNoDifference(savedCount, 1)
      let savedCourt = try await database.read { try Game.find(snapshot.game.id).fetchOne($0)?.court }
      expectNoDifference(savedCourt, "7")
    }

    @Test func failedDismissalSaveRestoresEditsForRetry() async throws {
      @Dependency(\.defaultDatabase) var database
      let snapshot = try savedGame()
      let store = TestStore(initialState: PlannedGameFeature.State(snapshot: snapshot)) { PlannedGameFeature() }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.editButtonTapped)
      await store.receive {
        if case .snapshotResponse(.edit, .success) = $0 {
          true
        } else {
          false
        }
      }
      await store.send(.editor(.presented(.binding(.allCasePaths.court.embed("7")))))
      try await database.write { try Game.find(snapshot.game.id).delete().execute($0) }
      await store.send(.editor(.dismiss))
      await store.receive {
        if case .editorDismissalSaved(.failure, _) = $0 {
          true
        } else {
          false
        }
      }
      expectNoDifference(store.state.editor?.court, "7")
      #expect(store.state.editor?.errorMessage != nil)
      #expect(store.state.editor?.failedSaveIntent == .close)
      let savedCount = try await database.read { try Game.fetchCount($0) }
      expectNoDifference(savedCount, 0)
      try await database.write { db in
        try Game.insert { snapshot.game }.execute(db)
        try GamePeriod.insert { snapshot.periods }.execute(db)
      }
      await store.send(.editor(.presented(.retrySaveButtonTapped)))
      await store.receive {
        if case .snapshotResponse(.refresh, .success) = $0 {
          true
        } else {
          false
        }
      }
      await store.finish()
      #expect(store.state.editor == nil)
      expectNoDifference(store.state.snapshot?.game.court, "7")
      let recovered = try await database.read { try GameSnapshot.fetch($0, gameID: snapshot.game.id) }
      expectNoDifference(recovered.game.court, "7")
    }

    @Test func unavailableGameCanRetryWithoutRecreatingIt() async throws {
      @Dependency(\.defaultDatabase) var database
      let snapshot = try savedGame()
      try await database.write { try Game.find(snapshot.game.id).delete().execute($0) }
      let store = Store(initialState: PlannedGameFeature.State(snapshot: snapshot)) { PlannedGameFeature() }
      await store.send(.startGameButtonTapped).finish()
      #expect(store.snapshot == nil)
      #expect(store.errorMessage != nil)
      #expect(!store.isLoading)
      // Restore the same record to represent a temporarily unavailable data source.
      try await database.write { db in
        try Game.insert { snapshot.game }.execute(db)
        try GamePeriod.insert { snapshot.periods }.execute(db)
      }
      await store.send(.retryButtonTapped).finish()
      #expect(store.errorMessage == nil)
      #expect(store.hasPreparedScoring)
      let savedCount = try await database.read { try Game.fetchCount($0) }
      expectNoDifference(savedCount, 1)
    }

    @Test(arguments: [false, true])
    func changedLifecycleRoutesAwayInsteadOfEditingOrPreparing(completed: Bool) async throws {
      @Dependency(\.defaultDatabase) var database
      let snapshot = try savedGame()
      try await database.write { db in
        try Game.find(snapshot.game.id).update {
          $0.startedAt = #bind(Date(timeIntervalSince1970: 1000))
          $0.endedAt = #bind(completed ? Date(timeIntervalSince1970: 2000) : nil)
        }.execute(db)
      }
      let store = TestStore(initialState: PlannedGameFeature.State(snapshot: snapshot)) { PlannedGameFeature() }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.editButtonTapped)
      await store.receive {
        if case .snapshotResponse(.edit, .success) = $0 {
          true
        } else {
          false
        }
      }
      await store.receive { action in
        guard case let .delegate(.lifecycleChanged(id)) = action else { return false }
        expectNoDifference(id, snapshot.game.id)
        return true
      }
      #expect(store.state.editor == nil)
      #expect(!store.state.hasPreparedScoring)
    }
  }
}
