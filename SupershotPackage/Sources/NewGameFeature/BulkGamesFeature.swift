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
    package var proposals: [String: Team] = [:]
    package var sharedDate: Date
    package var timeZoneID: String
    package var revision = 0

    package init() {
      @Dependency(\.date.now) var now
      @Dependency(\.timeZone) var timeZone
      sharedDate = now
      timeZoneID = timeZone.identifier
    }

    package func team(_ key: String?) -> Team? {
      guard let entry = review?.entries.first(where: { $0.id == key }) else { return nil }
      switch entry.selection {
      case let .existing(id): return savedTeams.first { $0.id == id }
      case .proposed: return proposals[entry.id]
      case nil: return nil
      }
    }

    package func draft(for row: Row) -> GameSetupDraft? {
      var setup = row.setup
      setup.leftTeam.team = team(row.firstKey)
      setup.rightTeam.team = team(row.secondKey)
      if let first = setup.leftTeam.team {
        setup.leftTeam.bibColor = .init(hex: first.colorHex)
      }
      if let second = setup.rightTeam.team {
        setup.rightTeam.bibColor = .init(hex: second.colorHex)
      }
      guard !row.needsScheduleReview, setup.scheduledAt != nil,
            var draft = setup.draft else { return nil }
      let ids = [draft.game.teamAID, draft.game.teamBID]
      draft.teamsToCreate = (review?.entries ?? []).compactMap { entry in
        guard entry.selection == .proposed, let team = proposals[entry.id], ids.contains(team.id) else { return nil }
        return team
      }
      guard draft.teamsToCreate.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
      return draft
    }

    package var selectedRows: [Row] {
      rows.filter(\.isSelected)
    }

    package var canSave: Bool {
      !isParsing && !isSaving && !didSave && !selectedRows.isEmpty
        && selectedRows.allSatisfy { draft(for: $0) != nil }
        && hasDistinctTeamNames
    }

    package var validationMessage: String? {
      if !hasDistinctTeamNames {
        return "Two different teams have the same name. Rename the new team or choose the same saved team."
      }
      return nil
    }

    private var hasDistinctTeamNames: Bool {
      let teams = selectedRows.flatMap { [team($0.firstKey), team($0.secondKey)].compactMap(\.self) }
      let unique = Dictionary(teams.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
      return Set(unique.map { FixtureTeamResolver.key(for: $0.name) }).count == unique.count
    }

    package var newTeamCount: Int {
      let keys = Set(selectedRows.flatMap { [$0.firstKey, $0.secondKey].compactMap(\.self) })
      return (review?.entries ?? []).filter { keys.contains($0.id) && $0.selection == .proposed }.count
    }

    package func listItem(for row: Row) -> GameListItem {
      let first = team(row.firstKey) ?? proposals[row.firstKey ?? ""]
      let second = team(row.secondKey) ?? proposals[row.secondKey ?? ""]
      return GameListItem(
        id: row.id,
        periods: row.setup.draft?.periods ?? [],
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
    package var isSelected = true
    package var needsScheduleReview = false
    package var needsTimeReview = false
    package var notices: [String] = []
    package var source: String
  }

  package enum Action: BindableAction {
    case binding(BindingAction<State>)
    case parseButtonTapped
    case parseResponse(Int, String, Result<ParsedBatch, any Error>)
    case backToInput
    case showPreview
    case selectTeam(String, FixtureTeamReview.Selection)
    case renameTeam(String, String)
    case changeParsedTeam(Game.ID, FixtureTeamReview.Side, String)
    case updateRow(Row)
    case applySharedDate
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
  }

  @Dependency(\.gameParser) var parser
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.uuid) var uuid
  @Dependency(\.dismiss) var dismiss

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
          referenceDate: state.sharedDate,
          timeZone: TimeZone(identifier: state.timeZoneID) ?? .current
        )
        return .run { send in
          let result = await Result {
            let fixtures = try await parser.parse(source, context: context)
            let teams = try await database.read { try Team.fetchAll($0) }
            return ParsedBatch(fixtures: fixtures, teams: teams, metadata: fixtures.map { DescribedGameMetadata(fixture: $0, context: context) })
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
            needsScheduleReview: metadata.scheduledAt == nil || fixture.date == nil || fixture.time == nil,
            needsTimeReview: fixture.time == nil,
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
        state.review?.editName(name, fixture: index, side: side)
        guard let review = state.review else { return .none }
        for index in state.rows.indices {
          state.rows[index].firstKey = review.references[index].first
          state.rows[index].secondKey = review.references[index].second
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
      case .applySharedDate:
        guard !state.isSaving else { return .none }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: state.timeZoneID) ?? .current
        let day = calendar.dateComponents([.year, .month, .day], from: state.sharedDate)
        for index in state.rows.indices {
          let time = calendar.dateComponents([.hour, .minute], from: state.rows[index].setup.scheduledAt ?? state.sharedDate)
          var components = day
          components.hour = time.hour
          components.minute = time.minute
          components.second = 0
          state.rows[index].setup.scheduledAt = calendar.date(from: components)
          let scheduled = state.rows[index].setup.scheduledAt
          let valid = scheduled.map { calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: $0) == components } ?? false
          state.rows[index].needsScheduleReview = state.rows[index].needsTimeReview || !valid
          if !state.rows[index].needsScheduleReview {
            state.rows[index].notices = []
          }
        }
        return .none
      case .saveButtonTapped:
        guard state.canSave else { return .none }
        state.isSaving = true
        state.errorMessage = nil
        let drafts = state.selectedRows.compactMap { state.draft(for: $0) }
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
      }
    }
  }

  private nonisolated enum CancelID { case parse }
  package init() {}
}
