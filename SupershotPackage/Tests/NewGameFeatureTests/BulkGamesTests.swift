import ClipboardClient
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
import Observation
import SQLiteData
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies { $0.timeZone = TimeZone(secondsFromGMT: 0)! })
  struct BulkGamesTests {
    private func store(
      source: String = "2026-11-03\n18:30 A vs B\n19:10 A vs C",
      now: Date = Date(timeIntervalSince1970: 1000),
      timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!
    ) throws -> StoreOf<BulkGamesFeature> {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      var state = BulkGamesFeature.State()
      state.source = source
      return Store(initialState: state) { BulkGamesFeature() } withDependencies: {
        $0.date.now = now
        $0.timeZone = timeZone
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

    @Test func timeOnlyRowsUseTodayAndDeletedRowsAreNotSaved() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try store(source: "18:30 A vs B\n19:10 A vs C")
      await store.send(.parseButtonTapped).finish()
      #expect(store.canSave)
      let secondID = store.rows[1].id
      await store.send(.deleteGame(secondID)).finish()
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

    @Test func missingTimeStillRequiresReview() async throws {
      let store = try store(source: "A vs B")
      let fixture = ExtractedFixture(source: store.source, firstTeam: "A", secondTeam: "B").validated(sourceLine: 1, context: nil)
      await store.send(.parseResponse(0, store.source, .success(.init(fixtures: [fixture], teams: [], metadata: [.init()])))).finish()
      #expect(!store.canSave)
      #expect(store.rows[0].needsScheduleReview)
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

    @Test func repeatedEditorBindingDoesNotCancelParsing() async {
      var state = BulkGamesFeature.State()
      state.source = "A vs B"
      state.parsingSource = state.source
      state.isParsing = true
      let store = TestStore(initialState: state) { BulkGamesFeature() }
      await store.send(.binding(.allCasePaths.source.embed("A vs B")))
      #expect(store.state.isParsing)
      await store.send(.binding(.allCasePaths.source.embed("A vs C"))) {
        $0.source = "A vs C"
        $0.isParsing = false
        $0.revision = 1
      }
    }

    @Test func previewReadsDoNotInvalidateObservedSetup() async throws {
      let store = try store()
      await store.send(.parseButtonTapped).finish()
      let state = store.state
      withObservationTracking {
        for row in state.rows {
          _ = row.setup.leftTeam
          _ = row.setup.rightTeam
        }
      } onChange: {
        Issue.record("Reading the preview changed observed setup, which can cause an infinite SwiftUI redraw loop.")
      }
      for _ in 0 ..< 3 {
        #expect(state.canSave)
        #expect(state.newTeamCount == 3)
        for row in state.rows {
          #expect(state.draft(for: row) != nil)
          #expect(state.listItem(for: row).periods.count == 4)
        }
      }
    }

    @Test(arguments: ["America/Los_Angeles", "Pacific/Auckland"])
    func missingDateUsesTodayInTheUsersTimeZone(zone: String) async throws {
      let now = try #require(ISO8601DateFormatter().date(from: "2026-11-03T00:30:00Z"))
      let timeZone = try #require(TimeZone(identifier: zone))
      let store = try store(source: "18:30 A vs B", now: now, timeZone: timeZone)
      await store.send(.parseButtonTapped).finish()
      let scheduled = try #require(store.rows.first?.setup.scheduledAt)
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = timeZone
      #expect(calendar.component(.year, from: scheduled) == 2026)
      #expect(calendar.component(.month, from: scheduled) == 11)
      #expect(calendar.component(.day, from: scheduled) == (zone == "America/Los_Angeles" ? 2 : 3))
      #expect(calendar.component(.hour, from: scheduled) == 18)
      #expect(calendar.component(.minute, from: scheduled) == 30)
      #expect(store.canSave)
      #expect(store.rows[0].notices.isEmpty)
    }

    @Test func explicitDateIsRetainedInTheUsersTimeZone() async throws {
      let now = try #require(ISO8601DateFormatter().date(from: "2026-11-03T00:30:00Z"))
      let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
      let store = try store(source: "2026-11-05\n18:30 A vs B", now: now, timeZone: timeZone)
      await store.send(.parseButtonTapped).finish()
      let scheduled = try #require(store.rows.first?.setup.scheduledAt)
      #expect(scheduled == ISO8601DateFormatter().date(from: "2026-11-06T02:30:00Z"))
      #expect(store.canSave)
    }

    @Test func deletingAnEarlierRowKeepsLaterTeamEditsOnTheCorrectFixture() async throws {
      let store = try store()
      await store.send(.parseButtonTapped).finish()
      let remainingID = store.rows[1].id
      await store.send(.deleteGame(store.rows[0].id)).finish()
      await store.send(.changeParsedTeam(remainingID, .second, "D")).finish()
      let key = try #require(store.rows[0].secondKey)
      await store.send(.selectTeam(key, .proposed)).finish()
      #expect(store.rows.count == 1)
      #expect(store.state.team(store.rows[0].firstKey)?.name == "A")
      #expect(store.state.team(store.rows[0].secondKey)?.name == "D")
      #expect(store.canSave)
      await store.send(.deleteGame(remainingID)).finish()
      #expect(!store.canSave)
      #expect(store.newTeamCount == 0)
    }

    @Test func previewRecognizesSavedGamesAndOnlySavesNewFixtures() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try store()
      await store.send(.parseButtonTapped).finish()
      let firstDraft = try #require(store.state.draft(for: store.rows[0]))
      try await database.write { db in _ = try firstDraft.save(db) }
      await store.send(.parseButtonTapped).finish()
      #expect(store.rows.count == 2)
      #expect(store.rowsToSave.count == 1)
      #expect(store.state.duplicateGameID(for: store.rows[0]) == firstDraft.game.id)
      #expect(store.newTeamCount == 1)
      await store.send(.saveButtonTapped).finish()
      try await database.read { db in
        try expectNoDifference(Game.fetchCount(db), 2)
        try expectNoDifference(Team.fetchCount(db), 3)
      }
    }

    @Test func savingRechecksForGamesCreatedAfterPreview() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try store(source: "2026-11-03\n18:30 A vs B")
      await store.send(.parseButtonTapped).finish()
      var concurrentDraft = try #require(store.state.draft(for: store.rows[0]))
      concurrentDraft.game = Game(
        id: UUID(999),
        startedAt: nil,
        teamAID: concurrentDraft.game.teamAID,
        teamBID: concurrentDraft.game.teamBID,
        createdAt: concurrentDraft.game.createdAt,
        scheduledAt: concurrentDraft.game.scheduledAt
      )
      concurrentDraft.periods = testGamePeriods(gameID: UUID(999))
      try await database.write { [concurrentDraft] db in _ = try concurrentDraft.save(db) }
      #expect(store.rowsToSave.count == 1)
      await store.send(.saveButtonTapped).finish()
      #expect(store.didSave)
      try await database.read { db in try expectNoDifference(Game.fetchCount(db), 1) }
    }

    @Test func repeatedFixturesInEitherTeamOrderAreOnlySavedOnce() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try store(source: "2026-11-03\n18:30 A vs B\n18:30 B vs A")
      await store.send(.parseButtonTapped).finish()
      #expect(store.rowsToSave.count == 1)
      let firstID = store.rows[0].id
      #expect(store.state.duplicateGameID(for: store.rows[1]) == firstID)
      await store.send(.deleteGame(firstID)).finish()
      #expect(store.rowsToSave.count == 1)
      #expect(store.state.duplicateGameID(for: store.rows[0]) == nil)
      await store.send(.saveButtonTapped).finish()
      try await database.read { db in try expectNoDifference(Game.fetchCount(db), 1) }
    }

    @Test func toolbarPasteUsesTheClipboardOnlyWhenRequested() async {
      let store = TestStore(initialState: BulkGamesFeature.State()) { BulkGamesFeature() } withDependencies: {
        $0.clipboard = .constant("18:30 A vs B")
      }
      await store.send(.pasteTapped) { $0.source = "18:30 A vs B" }
    }
  }
}
