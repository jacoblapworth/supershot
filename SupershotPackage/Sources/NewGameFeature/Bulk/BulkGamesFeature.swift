import ClipboardClient
import ComposableArchitecture
import Database
import FixtureTeamResolution
import Foundation
import GameCore
import GameParser
import SQLiteData
import UI

@Reducer
package struct BulkGamesFeature {
  @ObservableState
  package struct State: Equatable {
    package var source = ""
    package var parsedSource: String?
    package var showsPreview = false
    package var isParsing = false
    package var parsingSource: String?
    package var isSaving = false
    package var didSave = false
    package var errorMessage: String?
    package var rows: [Row] = []
    package var review: FixtureTeamReview?
    package var savedTeams: [Team] = []
    package var existingGames: [Game] = []
    package var proposals: [String: Team] = [:]
    package var revision = 0

    package init() {}

    package func team(_ key: String?) -> Team? {
      guard let entry = review?.entries.first(where: { $0.id == key }) else { return nil }
      switch entry.selection {
      case let .existing(id): return savedTeams.first { $0.id == id }
      case .proposed: return proposals[entry.id]
      case nil: return nil
      }
    }

    package func draft(for row: Row) -> GameSetupDraft? {
      guard !row.needsScheduleReview, row.setup.scheduledAt != nil,
            let first = team(row.firstKey), let second = team(row.secondKey) else { return nil }
      let ids = [first.id, second.id]
      let teamsToCreate: [Team] = (review?.entries ?? []).compactMap { entry in
        guard entry.selection == .proposed, let team = proposals[entry.id], ids.contains(team.id) else { return nil }
        return team
      }
      guard teamsToCreate.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
      return row.setup.draft(
        teamA: first,
        teamB: second,
        teamABibColorHex: first.colorHex,
        teamBBibColorHex: second.colorHex,
        teamsToCreate: teamsToCreate
      )
    }

    package func identity(for row: Row) -> GameFixtureIdentity? {
      guard let first = team(row.firstKey), let second = team(row.secondKey),
            let scheduledAt = row.setup.scheduledAt else { return nil }
      return GameFixtureIdentity(teamAID: first.id, teamBID: second.id, scheduledAt: scheduledAt)
    }

    package func duplicateGameID(for row: Row) -> Game.ID? {
      guard let identity = identity(for: row) else { return nil }
      if let existing = existingGames.first(where: { GameFixtureIdentity(game: $0) == identity }) {
        return existing.id
      }
      return rows.prefix(while: { $0.id != row.id }).first { self.identity(for: $0) == identity }?.id
    }

    package var rowsToSave: [Row] {
      rows.filter { duplicateGameID(for: $0) == nil }
    }

    package var canSave: Bool {
      !isParsing && !isSaving && !didSave && !rowsToSave.isEmpty
        && rowsToSave.allSatisfy { draft(for: $0) != nil }
        && hasDistinctTeamNames
    }

    package var validationMessage: String? {
      if rows.isEmpty {
        return "No games remain. Edit the text to preview another list."
      }
      if rowsToSave.isEmpty {
        return "These games already exist. No new games will be added."
      }
      if !hasDistinctTeamNames {
        return "Two different teams have the same name. Rename the new team or choose the same saved team."
      }
      return nil
    }

    private var hasDistinctTeamNames: Bool {
      let teams = rowsToSave.flatMap { [team($0.firstKey), team($0.secondKey)].compactMap(\.self) }
      let unique = Dictionary(teams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
      return Set(unique.map { FixtureTeamResolver.key(for: $0.name) }).count == unique.count
    }

    package var newTeamCount: Int {
      let keys = Set(rowsToSave.flatMap { [$0.firstKey, $0.secondKey].compactMap(\.self) })
      return (review?.entries ?? []).filter { keys.contains($0.id) && $0.selection == .proposed }.count
    }

    package func listItem(for row: Row) -> GameListItem {
      let first = team(row.firstKey) ?? proposals[row.firstKey ?? ""]
      let second = team(row.secondKey) ?? proposals[row.secondKey ?? ""]
      return GameListItem(
        id: row.id,
        periods: draft(for: row)?.periods ?? [],
        startedAt: nil,
        teamABibColorHex: first?.colorHex ?? "#007AFF",
        teamAName: first?.name ?? "Choose a team",
        teamAScore: 0,
        teamBBibColorHex: second?.colorHex ?? "#FF3B30",
        teamBName: second?.name ?? "Choose a team",
        teamBScore: 0,
        scheduledAt: row.setup.scheduledAt,
        court: row.setup.court,
        teamALogoData: first?.logoData,
        teamBLogoData: second?.logoData
      )
    }
  }

  package struct Row: Equatable, Identifiable {
    package var id: Game.ID {
      setup.gameID
    }

    package var setup: NewGameFeature.State
    package var firstKey: String?
    package var secondKey: String?
    package var fixtureIndex = 0
    package var needsScheduleReview = false
    package var notices: [String] = []
    package var source: String
  }

  package enum Action: BindableAction {
    case binding(BindingAction<State>)
    case pasteTapped
    case parseButtonTapped
    case parseResponse(Int, String, Result<ParsedBatch, any Error>)
    case backToInput
    case showPreview
    case deleteGame(Row.ID)
    case selectTeam(String, FixtureTeamReview.Selection)
    case renameTeam(String, String)
    case changeParsedTeam(Game.ID, FixtureTeamReview.Side, String)
    case updateRow(Row)
    case saveButtonTapped
    case saveResponse(Result<[GameSnapshot], any Error>)
    case cancelButtonTapped
    case delegate(Delegate)
    package enum Delegate { case saved }
  }

  package nonisolated struct ParsedBatch: Sendable {
    package var fixtures: [FixtureDraft]
    package var teams: [Team]
    package var metadata: [DescribedGameMetadata]
    package var games: [Game] = []
  }

  @Dependency(\.date.now) var now
  @Dependency(\.timeZone) var timeZone
  @Dependency(\.gameParser) var parser
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.uuid) var uuid
  @Dependency(\.dismiss) var dismiss
  @Dependency(\.clipboard) var clipboard

  package var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        state.errorMessage = nil
        if state.isParsing, state.source != state.parsingSource {
          state.isParsing = false
          state.revision += 1
          return .cancel(id: CancelID.parse)
        }
        return .none
      case .pasteTapped:
        guard !state.isParsing, !state.isSaving else { return .none }
        state.source = clipboard.paste() ?? state.source
        state.errorMessage = nil
        return .none
      case .parseButtonTapped:
        guard !state.isParsing, !state.isSaving else { return .none }
        state.revision += 1
        state.isParsing = true
        state.parsingSource = state.source
        state.errorMessage = nil
        let source = state.source
        let revision = state.revision
        let context = FixtureParsingContext(
          calendar: Calendar(identifier: .gregorian),
          referenceDate: now,
          timeZone: timeZone
        )
        return .run { send in
          let result = await Result {
            let fixtures = try await parser.parse(source, context: context)
            let (teams, games) = try await database.read { db in
              try (Team.fetchAll(db), Game.fetchAll(db))
            }
            return ParsedBatch(fixtures: fixtures, teams: teams, metadata: fixtures.map { DescribedGameMetadata(fixture: $0, context: context, inferMissingDate: true) }, games: games)
          }
          guard !Task.isCancelled else { return }
          await send(.parseResponse(revision, source, result))
        }.cancellable(id: CancelID.parse, cancelInFlight: true)
      case let .parseResponse(revision, source, .success(batch)):
        guard revision == state.revision, source == state.source else { return .none }
        state.isParsing = false
        state.parsingSource = nil
        state.parsedSource = source
        state.savedTeams = batch.teams
        state.existingGames = batch.games
        let review = FixtureTeamReview(fixtures: batch.fixtures, savedTeams: batch.teams)
        state.review = review
        state.proposals = [:]
        for (index, entry) in review.entries.enumerated() {
          state.proposals[entry.id] = Team(id: uuid(), name: entry.name, colorHex: ColorPalette.options[index % ColorPalette.options.count].color.hex())
        }
        state.rows = zip(batch.fixtures, batch.metadata).enumerated().map { index, pair in
          let (fixture, metadata) = pair
          var setup = NewGameFeature.State()
          setup.scheduledAt = metadata.scheduledAt
          setup.court = metadata.court ?? ""
          setup.division = metadata.division ?? ""
          return Row(
            setup: setup,
            firstKey: review.references[index].first,
            secondKey: review.references[index].second,
            fixtureIndex: index,
            needsScheduleReview: metadata.scheduledAt == nil || fixture.time == nil,
            notices: metadata.notices,
            source: fixture.source
          )
        }
        state.showsPreview = true
        return .none
      case let .parseResponse(revision, source, .failure(error)):
        guard revision == state.revision, source == state.source else { return .none }
        state.isParsing = false
        state.parsingSource = nil
        state.errorMessage = error.localizedDescription
        return .none
      case .backToInput:
        guard !state.isSaving else { return .none }
        state.showsPreview = false
        return .none
      case .showPreview:
        state.showsPreview = true
        return .none
      case let .selectTeam(key, selection):
        guard !state.isSaving else { return .none }
        try? state.review?.select(selection, for: key)
        return .none
      case let .changeParsedTeam(id, side, name):
        guard !state.isSaving, let index = state.rows.firstIndex(where: { $0.id == id }),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .none }
        let fixtureIndex = state.rows[index].fixtureIndex
        state.review?.editName(name, fixture: fixtureIndex, side: side)
        guard let review = state.review else { return .none }
        for index in state.rows.indices {
          let fixtureIndex = state.rows[index].fixtureIndex
          state.rows[index].firstKey = review.references[fixtureIndex].first
          state.rows[index].secondKey = review.references[fixtureIndex].second
        }
        for entry in review.entries where state.proposals[entry.id] == nil {
          state.proposals[entry.id] = Team(id: uuid(), name: entry.name, colorHex: ColorPalette.blue.hex())
        }
        return .none
      case let .renameTeam(key, name):
        guard !state.isSaving else { return .none }
        state.proposals[key]?.name = name
        return .none
      case let .updateRow(row):
        guard !state.isSaving, let index = state.rows.firstIndex(where: { $0.id == row.id }) else { return .none }
        state.rows[index] = row
        return .none
      case .saveButtonTapped:
        guard state.canSave else { return .none }
        state.isSaving = true
        state.errorMessage = nil
        let drafts = state.rowsToSave.compactMap { state.draft(for: $0) }
        let ids = Set(drafts.flatMap { [$0.game.teamAID, $0.game.teamBID] })
        let command = PlannedGameImport(drafts: drafts, matchedTeams: state.savedTeams.filter { ids.contains($0.id) })
        return .run { send in
          await send(.saveResponse(Result { try await database.write { try command.save($0) } }))
        }
      case .saveResponse(.success):
        state.isSaving = false
        state.didSave = true
        return .send(.delegate(.saved))
      case .saveResponse(.failure):
        state.isSaving = false
        state.errorMessage = "Could not save these games. No games were added. Your edits are still here. Check team matches and try again."
        return .none
      case .cancelButtonTapped:
        guard !state.isSaving else { return .none }
        return .run { _ in await dismiss() }
      case .delegate:
        return .none
      case let .deleteGame(id):
        guard !state.isSaving, !state.isParsing else { return .none }
        state.rows.removeAll(where: { $0.id == id })
        return .none
      }
    }
  }

  private nonisolated enum CancelID { case parse }
  package init() {}
}

package extension BulkGamesFeature.Row {
  static var preview: Self {
    .init(setup: NewGameFeature.State(), source: "")
  }
}
