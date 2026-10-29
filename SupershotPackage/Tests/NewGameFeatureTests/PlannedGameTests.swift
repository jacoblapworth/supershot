import ComposableArchitecture
import CustomDump
@testable import Database
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import GameCore
@testable import LocationClient
@testable import NewGameFeature
@testable import SharedModels
import SQLiteData
import SwiftUI
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(
    .dependencies {
      $0.uuid = .incrementing
      $0.date.now = Date(timeIntervalSince1970: 10000)
    }
  )
  struct PlannedGameTests {
    private func readySetup() async throws -> NewGameFeature.State {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let a = Team(id: UUID(101), name: "Ravens")
      let b = Team(id: UUID(102), name: "Swifts")
      try await database.write { db in
        try Team.insert {
          a
          b
        }.execute(db)
      }
      var state = NewGameFeature.State()
      state.leftTeam.team = a
      state.rightTeam.team = b
      return state
    }

    @Test(arguments: [0, 1, 2, 3])
    func savesValidSetupWithoutStarting(actionIndex: Int) async throws {
      @Dependency(\.defaultDatabase) var database
      var state = try await readySetup()
      state.court = "  A  "
      state.scheduledAt = Date(timeIntervalSince1970: 20000)
      let store = Store(initialState: state) { NewGameFeature() }
      let actions: [NewGameFeature.Action] = [
        .configurationChanged, .sceneBecameInactive, .closeButtonTapped, .saveGameButtonTapped,
      ]
      await store.send(actions[actionIndex]).finish()
      let saved = try await database.read { try GameSnapshot.fetch($0, gameID: state.gameID) }
      #expect(saved.game.isPlanned)
      #expect(saved.game.timerEndsAt == nil)
      expectNoDifference(saved.game.scheduledAt, state.scheduledAt)
      expectNoDifference(saved.game.court, "A")
      expectNoDifference(saved.periods.count, 4)
      #expect(!store.isSaving)
    }

    @Test
    func incompleteSetupDoesNotSave() async throws {
      @Dependency(\.defaultDatabase) var database
      var state = try await readySetup()
      state.rightTeam.team = nil
      let store = Store(initialState: state) { NewGameFeature() }
      await store.send(.closeButtonTapped).finish()
      let games = try await database.read { try Game.fetchAll($0) }
      expectNoDifference(games, [])
    }

    @Test(arguments: [-1000.0, 30000.0])
    func reopensEditsAndPreparesSameGameForScoring(scheduledTime: Double) async throws {
      @Dependency(\.defaultDatabase) var database
      var state = try await readySetup()
      state.scheduledAt = Date(timeIntervalSince1970: scheduledTime)
      state.court = "3"
      let store = Store(initialState: state) { NewGameFeature() }
      await store.send(.saveGameButtonTapped).finish()
      let saved = try await database.read { try GameSnapshot.fetch($0, gameID: state.gameID) }
      let restored = NewGameFeature.State(snapshot: saved)
      expectNoDifference(restored.draft, store.draft)
      let editor = Store(initialState: restored) { NewGameFeature() }
      editor.send(.binding(.set(\.court, "  B ")))
      await editor.send(.configurationChanged).finish()
      await editor.send(.configurationChanged).finish()
      await editor.send(.prepareScoringButtonTapped).finish()
      let (game, count) = try await database.read { db in
        try (Game.find(state.gameID).fetchOne(db), Game.fetchCount(db))
      }
      expectNoDifference(count, 1)
      #expect(game?.startedAt == nil)
      expectNoDifference(game?.scheduledAt, state.scheduledAt)
      expectNoDifference(game?.court, "B")
      #expect(game?.timerEndsAt == nil)
      #expect(editor.hasEnteredScoring)
    }

    @Test
    func failedSaveRetainsChangesAndCanRetry() async throws {
      @Dependency(\.defaultDatabase) var database
      let state = try await readySetup()
      let b = try #require(state.rightTeam.team)
      try await database.write { db in try Team.find(b.id).delete().execute(db) }
      let store = Store(initialState: state) { NewGameFeature() }
      await store.send(.closeButtonTapped).finish()
      #expect(store.errorMessage != nil)
      expectNoDifference(store.draft, state.draft)
      try await database.write { db in try Team.insert { b }.execute(db) }
      await store.send(.retrySaveButtonTapped).finish()
      #expect(store.errorMessage == nil)
      let games = try await database.read { try Game.fetchAll($0) }
      expectNoDifference(games.count, 1)
    }

    @Test
    func retryAfterFailedPreparationOpensSameGameForScoring() async throws {
      @Dependency(\.defaultDatabase) var database
      let state = try await readySetup()
      let b = try #require(state.rightTeam.team)
      try await database.write { db in try Team.find(b.id).delete().execute(db) }
      let store = Store(initialState: state) { NewGameFeature() }
      await store.send(.prepareScoringButtonTapped).finish()
      expectNoDifference(store.failedSaveIntent, .score)
      #expect(!store.hasEnteredScoring)
      try await database.write { db in try Team.insert { b }.execute(db) }
      await store.send(.retrySaveButtonTapped).finish()
      #expect(store.hasEnteredScoring)
      let games = try await database.read { try Game.fetchAll($0) }
      expectNoDifference(games.count, 1)
      expectNoDifference(games.first?.id, state.gameID)
      #expect(games.first?.isPlanned == true)
    }

    @Test
    func queuedScoringPreparationUsesLatestEditsWithoutDuplicatingGame() async throws {
      @Dependency(\.defaultDatabase) var database
      let state = try await readySetup()
      let store = Store(initialState: state) { NewGameFeature() }
      let saving = store.send(.configurationChanged)
      store.send(.binding(.set(\.court, "4")))
      store.send(.prepareScoringButtonTapped)
      await saving.finish()
      let games = try await database.read { try Game.fetchAll($0) }
      expectNoDifference(games.count, 1)
      expectNoDifference(games.first?.court, "4")
      #expect(games.first?.isPlanned == true)
    }

    @Test
    func invalidEditsKeepLastSavedSetup() async throws {
      @Dependency(\.defaultDatabase) var database
      let state = try await readySetup()
      let store = Store(initialState: state) { NewGameFeature() }
      await store.send(.configurationChanged).finish()
      var invalid = store.withState { $0 }
      invalid.periodDuration = .init(totalSeconds: 0)
      let editor = Store(initialState: invalid) { NewGameFeature() }
      await editor.send(.closeButtonTapped).finish()
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: state.gameID) }
      expectNoDifference(snapshot.periods.first?.durationSeconds, 480)
    }

    @Test
    func switchingToNowClearsScheduleAndBlankCourt() async throws {
      var state = try await readySetup()
      state.scheduledAt = Date(timeIntervalSince1970: 20000)
      state.court = " \n "
      let store = Store(initialState: state) { NewGameFeature() }
      store.send(.binding(.set(\.scheduledAt, nil)))
      #expect(store.scheduledAt == nil)
      #expect(store.draft?.game.court == nil)
    }

    @Test
    func restoredLocationIsNotReplacedOnAppearance() async throws {
      var state = try await readySetup()
      let location = GameLocation(latitude: 1, longitude: 2, pointOfInterestName: "Arena")
      state.location = .loaded(location)
      state.requiresExistingGame = true
      let store = Store(initialState: state) { NewGameFeature() }
      await store.send(.task).finish()
      await store.send(.sceneBecameActive).finish()
      expectNoDifference(store.location, .loaded(location))
    }
  }
}
