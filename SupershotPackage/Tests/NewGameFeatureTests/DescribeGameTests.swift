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
import Styleguide
import SwiftUI
import TeamEditingFeature
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.timeZone = TimeZone(secondsFromGMT: 0)!
    $0.withRandomNumberGenerator = .init(SystemRandomNumberGenerator())
  })
  struct DescribeGameTests {
    private static let description = "Ravens vs Swifts tomorrow 7:30pm Court 2 Division A"

    private nonisolated static func row(_ source: String) -> [ExtractedFixture] {
      [ExtractedFixture(
        source: source, firstTeam: "Ravens", secondTeam: "Swifts",
        date: source.contains("tomorrow") ? "tomorrow" : nil,
        time: source.contains("7:30pm") ? "7:30pm" : nil,
        division: source.contains("Division A") ? "Division A" : nil,
        court: source.contains("Court 2") ? "Court 2" : nil
      )]
    }

    private func setup(
      teams: [Team] = [], state: NewGameFeature.State = .init(),
      generate: @escaping @Sendable (String) async throws -> [ExtractedFixture] = { DescribeGameTests.row($0) }
    ) async throws -> StoreOf<NewGameFeature> {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      try await database.write { db in
        for team in teams {
          try Team.insert { team }.execute(db)
        }
      }
      return Store(initialState: state) { NewGameFeature() } withDependencies: {
        $0.gameParser = GameParser(availability: { .available }, generate: generate)
      }
    }

    @Test
    func pasteAutomaticallyPopulatesSavedTeamsAndMetadata() async throws {
      let a = Team(id: UUID(100), name: "Ravens", colorHex: "#123456")
      let b = Team(id: UUID(101), name: "Swifts", colorHex: "#654321")
      let store = try await setup(teams: [a, b])
      await store.send(.describeGame(.pasted(Self.description))).finish()
      expectNoDifference(store.leftTeam.team, a)
      expectNoDifference(store.rightTeam.team, b)
      expectNoDifference(store.scheduledAt, Date(timeIntervalSince1970: 86400 + 19 * 3600 + 30 * 60))
      #expect(store.court == "2")
      #expect(store.division == "A")
      #expect(store.canStartGame)
      #expect(!store.hasStarted)
      #expect(store.describeGame.pendingTeams.isEmpty)
    }

    @Test
    func exactReportedInputResolvesSavedTeamsAndPopulatesScheduledTime() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let a = Team(id: UUID(100), name: "The lodgers")
      let b = Team(id: UUID(101), name: "IMG & Friends")
      try await database.write { db in
        try Team.insert { a; b }.execute(db)
      }
      let store = Store(initialState: NewGameFeature.State()) { NewGameFeature() } withDependencies: {
        $0.gameParser = .live
      }
      await store.send(.describeGame(.pasted("19:10  The lodgers vs IMG & Friends"))).finish()
      expectNoDifference(store.leftTeam.team, a)
      expectNoDifference(store.rightTeam.team, b)
      expectNoDifference(store.scheduledAt, Date(timeIntervalSince1970: 19 * 3600 + 10 * 60))
      #expect(store.canStartGame)
      #expect(store.describeGame.errorMessage == nil)
    }

    @Test
    func typingParsesAfterDebounceWithoutSubmitting() async {
      let clock = TestClock()
      let store = TestStore(initialState: DescribeGameFeature.State()) { DescribeGameFeature() } withDependencies: {
        $0.continuousClock = clock
        $0.gameParser = GameParser(availability: { .available }, generate: { DescribeGameTests.row($0) })
      }
      store.exhaustivity = .off
      await store.send(.binding(.set(\.source, "Ravens")))
      await clock.advance(by: .milliseconds(300))
      await store.send(.binding(.set(\.source, "Ravens vs Swifts")))
      await clock.advance(by: .milliseconds(499))
      #expect(store.state.review == nil)
      #expect(store.state.isDebouncing)
      await clock.advance(by: .milliseconds(1))
      await store.receive(\.parse)
      await store.receive(\.parseResponse)
      await store.receive(\.delegate)
      #expect(store.state.team(for: .first)?.name == "Ravens")
      #expect(store.state.team(for: .second)?.name == "Swifts")
      #expect(!store.state.isBusy)
      await store.finish()
    }

    @Test
    func newTeamsAreReadyWithoutConfirmationAndSavedAtomicallyOnStart() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try await setup()
      await store.send(.describeGame(.pasted(Self.description))).finish()
      let a = try #require(store.leftTeam.team)
      let b = try #require(store.rightTeam.team)
      #expect(a.name == "Ravens")
      #expect(b.name == "Swifts")
      #expect(a.colorHex != b.colorHex)
      #expect(store.canStartGame)
      await store.send(.configurationChanged).finish()
      await store.send(.sceneBecameInactive).finish()
      let before = try await database.read { try (Team.fetchCount($0), Game.fetchCount($0)) }
      #expect(before.0 == 0)
      #expect(before.1 == 0)
      await store.send(.startGameButtonTapped).finish()
      #expect(store.hasStarted)
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: store.gameID) }
      expectNoDifference(snapshot.teamA, a)
      expectNoDifference(snapshot.teamB, b)
      #expect(snapshot.game.startedAt != nil)
      #expect(snapshot.game.court == "2")
      #expect(snapshot.game.division == "A")
    }

    @Test
    func savePersistsMetadataWithoutStartingAndRepeatedTapsDoNotDuplicate() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try await setup()
      await store.send(.describeGame(.pasted(Self.description))).finish()
      let saving = store.send(.saveGameButtonTapped)
      store.send(.saveGameButtonTapped)
      await saving.finish()
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: store.gameID) }
      #expect(snapshot.game.isPlanned)
      #expect(snapshot.game.court == "2")
      #expect(snapshot.game.division == "A")
      let restored = NewGameFeature.State(snapshot: snapshot)
      #expect(restored.court == "2")
      #expect(restored.division == "A")
      let counts = try await database.read { try (Team.fetchCount($0), Game.fetchCount($0)) }
      #expect(counts.0 == 2)
      #expect(counts.1 == 1)
    }

    @Test
    func clearRemovesEveryPopulatedFieldRatherThanRestoringOldValues() async throws {
      @Dependency(\.defaultDatabase) var database
      var state = NewGameFeature.State()
      state.scheduledAt = Date(timeIntervalSince1970: 5000)
      state.court = "Original court"
      state.division = "Original division"
      let store = try await setup(state: state)
      await store.send(.describeGame(.pasted(Self.description))).finish()
      await store.send(.describeGame(.clearButtonTapped)).finish()
      #expect(store.describeGame.source.isEmpty)
      #expect(store.describeGame.review == nil)
      #expect(store.leftTeam.team == nil)
      #expect(store.rightTeam.team == nil)
      #expect(store.scheduledAt == nil)
      #expect(store.court.isEmpty)
      #expect(store.division.isEmpty)
      #expect(store.parsedFields.isEmpty)
      #expect(!store.canStartGame)
      let counts = try await database.read { try (Team.fetchCount($0), Game.fetchCount($0)) }
      #expect(counts.0 == 0)
      #expect(counts.1 == 0)
    }

    @Test
    func clearPreservesManualFieldsThatWereNeverPopulatedByParsing() async throws {
      var state = NewGameFeature.State()
      state.court = "Manual court"
      state.division = "Manual division"
      state.scheduledAt = Date(timeIntervalSince1970: 5000)
      let store = try await setup(state: state)
      await store.send(.describeGame(.pasted("Ravens vs Swifts"))).finish()
      await store.send(.describeGame(.binding(.set(\.source, "")))).finish()
      #expect(store.leftTeam.team == nil)
      #expect(store.rightTeam.team == nil)
      #expect(store.court == "Manual court")
      #expect(store.division == "Manual division")
      expectNoDifference(store.scheduledAt, state.scheduledAt)
    }

    @Test
    func replacingDescriptionRemovesMetadataNoLongerPresent() async throws {
      let store = try await setup()
      await store.send(.describeGame(.pasted(Self.description))).finish()
      await store.send(.describeGame(.pasted("Ravens vs Swifts"))).finish()
      #expect(store.scheduledAt == nil)
      #expect(store.court.isEmpty)
      #expect(store.division.isEmpty)
      #expect(store.leftTeam.team?.name == "Ravens")
      #expect(store.canStartGame)
    }

    @Test
    func clearCancelsDebounceBeforeGeneration() async {
      let clock = TestClock()
      let store = TestStore(initialState: DescribeGameFeature.State()) { DescribeGameFeature() } withDependencies: {
        $0.continuousClock = clock
        $0.gameParser = GameParser(availability: { .available }, generate: { _ in
          Issue.record("Cleared input must not generate")
          return []
        })
      }
      store.exhaustivity = .off
      await store.send(.binding(.set(\.source, "Ravens vs Swifts")))
      await store.send(.clearButtonTapped)
      await store.receive(\.delegate)
      await clock.advance(by: .seconds(1))
      #expect(store.state.source.isEmpty)
      #expect(!store.state.isBusy)
      await store.finish()
    }

    @Test
    func clearDuringParseDoesNotRepopulateSetup() async throws {
      let store = try await setup(generate: { source in
        try await Task.sleep(for: .milliseconds(50))
        return DescribeGameTests.row(source)
      })
      let parsing = store.send(.describeGame(.pasted(Self.description)))
      await store.send(.describeGame(.clearButtonTapped)).finish()
      await parsing.finish()
      #expect(store.describeGame.source.isEmpty)
      #expect(store.describeGame.review == nil)
      #expect(store.leftTeam.team == nil)
      #expect(store.scheduledAt == nil)
    }

    @Test
    func staleResponseCannotRepopulateAfterClearingAndReusingSameText() async throws {
      let store = try await setup()
      await store.send(.describeGame(.pasted(Self.description))).finish()
      let revision = store.describeGame.revision
      let fixtures = try #require(store.describeGame.review?.fixtures)
      await store.send(.describeGame(.clearButtonTapped)).finish()
      await store.send(.describeGame(.pasted(Self.description))).finish()
      await store.send(.describeGame(.parseResponse(revision, Self.description, .success(
        DescribeGameFeature.ParsedMatchup(
          fixtures: fixtures, teams: [],
          metadata: DescribedGameMetadata(court: "Wrong court")
        )
      )))).finish()
      await store.send(.describeGame(.delegate(.populated(
        revision, nil, nil, DescribedGameMetadata(court: "Stale court")
      )))).finish()
      await store.send(.describeGame(.delegate(.cleared(revision + 1)))).finish()
      #expect(store.court == "2")
      #expect(store.leftTeam.team?.name == "Ravens")
    }

    @Test
    func parsedSavedTeamUsesExistingConfigurationAndReplacementPicker() async throws {
      let a = Team(id: UUID(100), name: "Ravens")
      let b = Team(id: UUID(101), name: "Swifts")
      let replacement = Team(id: UUID(102), name: "Falcons")
      let store = try await setup(teams: [a, b, replacement], generate: { source in
        [ExtractedFixture(source: source, firstTeam: "Raven", secondTeam: "Swifts")]
      })
      await store.send(.describeGame(.pasted("Raven vs Swifts"))).finish()
      expectNoDifference(store.leftTeam.team, a)
      store.send(.selectTeamButtonTapped(.teamA))
      guard case let .teamConfiguration(configuration) = store.destination else {
        Issue.record("A saved parsed team must open the existing configuration")
        return
      }
      expectNoDifference(configuration.configuration.savedTeam, a)
      store.send(.destination(.presented(.teamConfiguration(.configuration(.changeTeamButtonTapped)))))
      await store.send(.destination(.presented(.teamConfiguration(.configuration(
        .picker(.presented(.teamSelected(replacement)))
      ))))).finish()
      expectNoDifference(store.leftTeam.team, replacement)
      #expect(store.canStartGame)
      #expect(store.draft?.teamsToCreate.isEmpty == true)
    }

    private func pickerEditor(_ action: TeamEditorFeature.Action) -> NewGameFeature.Action {
      .destination(.presented(.teamPicker(.picker(.editor(.presented(action))))))
    }

    @Test
    func proposedTeamUsesExistingPickerAndPrefilledCreateFlow() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try await setup()
      await store.send(.describeGame(.pasted(Self.description))).finish()
      let proposal = try #require(store.rightTeam.team)
      let opponent = try #require(store.leftTeam.team)
      store.send(.selectTeamButtonTapped(.teamB))
      guard case let .teamPicker(picker) = store.destination else {
        Issue.record("A proposed team must open the existing picker")
        return
      }
      #expect(picker.picker.searchText == proposal.name)
      expectNoDifference(picker.picker.proposedTeam, proposal)
      #expect(picker.picker.excludedTeamIDs == [opponent.id])
      store.send(.destination(.presented(.teamPicker(.picker(.createTeamButtonTapped)))))
      guard case let .teamPicker(creating) = store.destination,
            let editor = creating.picker.editor
      else {
        Issue.record("Create must open the existing team editor")
        return
      }
      #expect(editor.name == proposal.name)
      #expect(editor.color == proposal.color)
      store.send(pickerEditor(.binding(.set(\.name, "Corrected Swifts"))))
      await store.send(pickerEditor(.saveButtonTapped)).finish()
      let selected = try #require(store.rightTeam.team)
      #expect(selected.name == "Corrected Swifts")
      #expect(selected.colorHex == proposal.colorHex)
      #expect(selected.id != proposal.id)
      #expect(store.destination == nil)
      #expect(store.draft?.teamsToCreate.map(\.id) == [opponent.id])
      store.send(.destinationDidDismiss)
      guard case let .teamConfiguration(configuration) = store.destination else {
        Issue.record("The created team must use the existing configuration flow")
        return
      }
      expectNoDifference(configuration.configuration.savedTeam, selected)
      await store.send(.destination(.presented(.teamConfiguration(.configuration(.doneButtonTapped))))).finish()
      #expect(store.canStartGame)
      await store.send(.saveGameButtonTapped).finish()
      let teams = try await database.read { try Team.fetchAll($0) }
      #expect(teams.count == 2)
      #expect(!teams.contains { $0.id == proposal.id })
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: store.gameID) }
      expectNoDifference(snapshot.teamB, selected)
    }

    @Test
    func cancellingProposedTeamPickerKeepsAutomaticSelectionWithoutWrites() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try await setup()
      await store.send(.describeGame(.pasted(Self.description))).finish()
      let original = store.rightTeam.team
      store.send(.selectTeamButtonTapped(.teamB))
      await store.send(.destination(.presented(.teamPicker(.picker(.cancelButtonTapped))))).finish()
      expectNoDifference(store.rightTeam.team, original)
      #expect(store.destination == nil)
      #expect(store.canStartGame)
      let count = try await database.read { try Team.fetchCount($0) }
      #expect(count == 0)
    }

    @Test
    func pickerCanCorrectIdenticalParsedNamesWithoutDuplicatingPendingTeams() async throws {
      let saved = Team(id: UUID(100), name: "Swifts")
      let store = try await setup(teams: [saved], generate: { source in
        [ExtractedFixture(source: source, firstTeam: "Ravens", secondTeam: "Ravens")]
      })
      await store.send(.describeGame(.pasted("Ravens vs Ravens"))).finish()
      #expect(!store.canStartGame)
      store.send(.selectTeamButtonTapped(.teamB))
      await store.send(.destination(.presented(.teamPicker(.picker(.teamSelected(saved)))))).finish()
      #expect(store.canStartGame)
      #expect(store.draft?.teamsToCreate.count == 1)
      await store.send(.saveGameButtonTapped).finish()
      #expect(store.errorMessage == nil)
    }

    @Test
    func swappingMovesParsedOwnershipWithTheTeamWhenClearing() async throws {
      let manual = Team(id: UUID(100), name: "Manual team")
      var state = NewGameFeature.State()
      state.rightTeam.team = manual
      let store = try await setup(teams: [manual], state: state, generate: { source in
        [ExtractedFixture(source: source, firstTeam: "Ravens")]
      })
      await store.send(.describeGame(.pasted("Ravens"))).finish()
      #expect(store.canSwapTeams)
      store.send(.swapTeamsButtonTapped)
      await store.send(.describeGame(.clearButtonTapped)).finish()
      expectNoDifference(store.leftTeam.team, manual)
      #expect(store.rightTeam.team == nil)
    }

    @Test
    func failureRollsBackTeamsAndRetrySavesWithoutDuplicates() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try await setup()
      await store.send(.describeGame(.pasted(Self.description))).finish()
      try await database.write { db in
        try #sql("""
        CREATE TRIGGER reject_parsed_game BEFORE INSERT ON games
        BEGIN SELECT RAISE(ABORT, 'Test failure'); END
        """).execute(db)
      }
      await store.send(.saveGameButtonTapped).finish()
      #expect(store.errorMessage != nil)
      let counts = try await database.read { try (Team.fetchCount($0), Game.fetchCount($0)) }
      #expect(counts.0 == 0)
      #expect(counts.1 == 0)
      try await database.write { try #sql("DROP TRIGGER reject_parsed_game").execute($0) }
      await store.send(.retrySaveButtonTapped).finish()
      let finalCounts = try await database.read { try (Team.fetchCount($0), Game.fetchCount($0)) }
      #expect(finalCounts.0 == 2)
      #expect(finalCounts.1 == 1)
    }

    @Test
    func deletedSavedTeamFailsWithoutLeavingProposedTeams() async throws {
      @Dependency(\.defaultDatabase) var database
      let saved = Team(id: UUID(100), name: "Ravens")
      let store = try await setup(teams: [saved])
      await store.send(.describeGame(.pasted(Self.description))).finish()
      try await database.write { try Team.find(saved.id).delete().execute($0) }
      await store.send(.saveGameButtonTapped).finish()
      #expect(store.errorMessage != nil)
      let counts = try await database.read { try (Team.fetchCount($0), Game.fetchCount($0)) }
      #expect(counts.0 == 0)
      #expect(counts.1 == 0)
    }

    @Test
    func multipleFixturesAreRejectedWithoutPersistingAnything() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try await setup(generate: { _ in
        [
          ExtractedFixture(source: "A vs B", firstTeam: "A", secondTeam: "B"),
          ExtractedFixture(source: "C vs D", firstTeam: "C", secondTeam: "D"),
        ]
      })
      await store.send(.describeGame(.pasted("A vs B\nC vs D"))).finish()
      #expect(store.describeGame.errorMessage?.contains("Batch import") == true)
      #expect(store.leftTeam.team == nil)
      let counts = try await database.read { try (Team.fetchCount($0), Game.fetchCount($0)) }
      #expect(counts.0 == 0)
      #expect(counts.1 == 0)
    }

    @Test
    func unavailableModelLeavesManualSetupUsable() async {
      let store = Store(initialState: NewGameFeature.State()) { NewGameFeature() } withDependencies: {
        $0.gameParser = GameParser(availability: { .modelNotReady }, generate: { _ in
          Issue.record("Unavailable model must not generate")
          return []
        })
      }
      await store.send(.describeGame(.pasted(Self.description))).finish()
      #expect(store.describeGame.errorMessage != nil)
      #expect(!store.describeGame.isBusy)
      await store.send(.describeGame(.clearButtonTapped)).finish()
      store.send(.selectTeamButtonTapped(.teamA))
      #expect(store.destination != nil)
    }

    @Test
    func closingImplicitSetupDoesNotCreateTeamsOrGame() async throws {
      @Dependency(\.defaultDatabase) var database
      let store = try await setup()
      await store.send(.describeGame(.pasted(Self.description))).finish()
      await store.send(.closeButtonTapped).finish()
      let counts = try await database.read { try (Team.fetchCount($0), Game.fetchCount($0)) }
      #expect(counts.0 == 0)
      #expect(counts.1 == 0)
    }
  }
}
