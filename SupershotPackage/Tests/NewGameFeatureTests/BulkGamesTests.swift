import ComposableArchitecture
import CustomDump
import Database
import Dependencies
import DependenciesTestSupport
import FixtureTeamResolution
import Foundation
import GameCore
@testable import GameParser
@testable import NewGameFeature
import SQLiteData
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies { $0.timeZone = TimeZone(secondsFromGMT: 0)! })
  struct BulkGamesTests {
    private func store(source: String = "2026-11-03\n18:30 A vs B\n19:10 A vs C") throws -> StoreOf<BulkGamesFeature> {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      var state = BulkGamesFeature.State()
      state.source = source
      return Store(initialState: state) { BulkGamesFeature() } withDependencies: {
        $0.timeZone = TimeZone(secondsFromGMT: 0)!
        $0.gameParser = GameParser(availability: { .unavailable }, generate: { _ in [] }, extractStructured: StructuredFixtureExtractor.extract)
      }
    }

    @Test func previewIsTransientAndRepeatedTeamsShareIdentity() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try store()
      await store.send(.parseButtonTapped).finish()
      #expect(store.rows.count == 2)
      #expect(store.canSave)
      #expect(store.newTeamCount == 3)
      #expect(store.state.team(store.rows[0].firstKey)?.id == store.state.team(store.rows[1].firstKey)?.id)
      try await database.read { db in
        try expectNoDifference(Game.fetchCount(db), 0)
        try expectNoDifference(Team.fetchCount(db), 0)
      }
      let id = store.rows[0].id
      await store.send(.backToInput).finish()
      await store.send(.showPreview).finish()
      #expect(store.rows[0].id == id)
      await store.send(.saveButtonTapped).finish()
      #expect(store.didSave)
      #expect(!store.canSave)
      await store.send(.saveButtonTapped).finish()
      try await database.read { db in
        try expectNoDifference(Game.fetchCount(db), 2)
        try expectNoDifference(Team.fetchCount(db), 3)
      }
    }

    @Test func sharedDateConfirmsTimeOnlyRowsAndDeselectionExcludesGames() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try store(source: "18:30 A vs B\n19:10 A vs C")
      await store.send(.parseButtonTapped).finish()
      #expect(!store.canSave)
      await store.send(.applySharedDate).finish()
      #expect(store.canSave)
      var second = store.rows[1]
      second.isSelected = false
      await store.send(.updateRow(second)).finish()
      #expect(store.newTeamCount == 2)
      await store.send(.saveButtonTapped).finish()
      try await database.read { db in
        try expectNoDifference(Game.fetchCount(db), 1)
        try expectNoDifference(Team.fetchCount(db), 2)
      }
    }

    @Test func failedSavePreservesEditedRowsAndCanRetry() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try store()
      await store.send(.parseButtonTapped).finish()
      let aKey = try #require(store.rows[0].firstKey)
      let a = try #require(store.proposals[aKey])
      // Simulate a concurrent conflicting identity after preview.
      try await database.write { db in try Team.insert { Team(id: a.id, name: "Conflicting") }.execute(db) }
      await store.send(.saveButtonTapped).finish()
      #expect(store.errorMessage != nil)
      #expect(store.rows.count == 2)
      #expect(!store.isSaving)
      #expect(!store.didSave)
      try await database.read { db in try expectNoDifference(Game.fetchCount(db), 0) }
      try await database.write { db in try Team.find(a.id).delete().execute(db) }
      await store.send(.saveButtonTapped).finish()
      #expect(store.didSave)
    }

    @Test func duplicateTeamRenameBlocksSave() async throws {
      let store = try store()
      await store.send(.parseButtonTapped).finish()
      let key = try #require(store.rows[0].secondKey)
      await store.send(.renameTeam(key, "A")).finish()
      #expect(!store.canSave)
    }

    @Test func savedMatchesAreReusedAndAmbiguousMatchesRequireReview() async throws {
      let store = try store()
      let a = Team(id: UUID(100), name: "A")
      let firstB = Team(id: UUID(101), name: "B")
      let secondB = Team(id: UUID(102), name: "b")
      let source = store.source
      let fixture = ExtractedFixture(source: source, firstTeam: "A", secondTeam: "B", date: "2026-11-03", time: "18:30").validated(sourceLine: 1, context: nil)
      await store.send(.parseResponse(0, source, .success(.init(fixtures: [fixture], teams: [a, firstB, secondB], metadata: [.init(scheduledAt: Date(timeIntervalSince1970: 2000))])))).finish()
      #expect(store.state.team(store.rows[0].firstKey)?.id == a.id)
      #expect(!store.canSave)
      let key = try #require(store.rows[0].secondKey)
      await store.send(.selectTeam(key, .existing(firstB.id))).finish()
      #expect(store.canSave)
      #expect(store.newTeamCount == 0)
    }

    @Test func staleParseResponseDoesNotReplaceEditedPreview() async throws {
      let store = try store()
      await store.send(.parseButtonTapped).finish()
      let rows = store.rows
      await store.send(.parseResponse(0, "old text", .failure(GameParserError.generationFailed))).finish()
      #expect(store.errorMessage == nil)
      #expect(store.rows == rows)
    }

    @Test func unavailableModelShowsAnErrorWithoutWrites() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try store(source: "A against B tomorrow")
      await store.send(.parseButtonTapped).finish()
      #expect(store.errorMessage != nil)
      #expect(store.rows.isEmpty)
      #expect(!store.isParsing)
      try await database.read { db in try expectNoDifference(Game.fetchCount(db), 0) }
    }

    @Test func missingTimeStillRequiresReviewAfterApplyingSharedDate() async throws {
      let store = try store(source: "A vs B")
      let fixture = ExtractedFixture(source: store.source, firstTeam: "A", secondTeam: "B").validated(sourceLine: 1, context: nil)
      await store.send(.parseResponse(0, store.source, .success(.init(fixtures: [fixture], teams: [], metadata: [.init()])))).finish()
      await store.send(.applySharedDate).finish()
      #expect(!store.canSave)
      #expect(store.rows[0].needsTimeReview)
    }

    @Test func correctingOneOccurrenceCanSeparateIdenticalParsedTeams() async throws {
      let store = try store(source: "2026-11-03\n18:30 A vs A")
      await store.send(.parseButtonTapped).finish()
      #expect(!store.canSave)
      let id = store.rows[0].id
      await store.send(.changeParsedTeam(id, .second, "B")).finish()
      let secondKey = try #require(store.rows[0].secondKey)
      await store.send(.selectTeam(secondKey, .proposed)).finish()
      #expect(store.canSave)
      #expect(store.state.team(store.rows[0].firstKey)?.name == "A")
      #expect(store.state.team(store.rows[0].secondKey)?.name == "B")
    }
  }
}
