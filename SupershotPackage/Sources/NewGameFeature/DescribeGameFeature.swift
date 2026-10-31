import AppUI
import ComposableArchitecture
import Database
import FixtureTeamResolution
import Foundation
import GameCore
import GameParser
import SQLiteData
import UI

/// Extraction is automatic; proposals remain transient until normal game persistence.
@Reducer
package struct DescribeGameFeature {
  @ObservableState
  package struct State: Equatable {
    package var source = ""
    package var revision = 0
    package var parsedSource: String?
    package var availability: GameParserAvailability = .available
    package var isDebouncing = false
    package var isParsing = false
    package var errorMessage: String?
    package var metadataNotices: [String] = []
    package var review: FixtureTeamReview?
    package var savedTeams: [Team] = []
    package var proposals: [String: Team] = [:]

    package var isBusy: Bool {
      isDebouncing || isParsing
    }

    package func entry(for side: FixtureTeamReview.Side) -> FixtureTeamReview.Entry? {
      guard let reference = review?.references.first else { return nil }
      let key = side == .first ? reference.first : reference.second
      return review?.entries.first { $0.id == key }
    }

    package func team(for side: FixtureTeamReview.Side) -> Team? {
      guard let entry = entry(for: side) else { return nil }
      if case let .existing(id) = entry.selection {
        return savedTeams.first { $0.id == id }
      }
      return proposals[entry.id]
    }

    package var pendingTeams: [Team] {
      var seen: Set<Team.ID> = []
      return [FixtureTeamReview.Side.first, .second].compactMap { side -> Team? in
        guard let entry = entry(for: side), entry.selection == .proposed,
              var team = proposals[entry.id], seen.insert(team.id).inserted else { return nil }
        team.name = team.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return team
      }
    }
  }

  package enum Action: BindableAction {
    case binding(BindingAction<State>)
    case task
    case pasted(String)
    case parse
    case parseResponse(Int, String, Result<ParsedMatchup, any Error>)
    case clearButtonTapped
    case delegate(Delegate)

    package enum Delegate {
      case populated(Int, Team?, Team?, DescribedGameMetadata)
      case cleared(Int)
    }
  }

  package nonisolated struct ParsedMatchup: Sendable {
    package var fixtures: [FixtureDraft]
    package var teams: [Team]
    package var metadata: DescribedGameMetadata
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.date.now) var now
  @Dependency(\.timeZone) var timeZone
  @Dependency(\.gameParser) var parser
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.uuid) var uuid
  @Dependency(\.withRandomNumberGenerator) var random

  package var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .task:
        state.availability = parser.availability()
        return .none

      case .binding:
        return sourceChanged(state: &state, immediately: false)

      case let .pasted(text):
        state.source = text
        return sourceChanged(state: &state, immediately: true)

      case .parse:
        guard !state.source.isEmpty else { return .none }
        state.isDebouncing = false
        state.availability = parser.availability()
        state.isParsing = true
        let source = state.source
        let revision = state.revision
        let context = FixtureParsingContext(
          calendar: Calendar(identifier: .gregorian), referenceDate: now, timeZone: timeZone
        )
        return .run { send in
          let result = await Result {
            let fixtures = try await parser.parse(source, context: context)
            guard fixtures.count == 1 else { throw ParsingError.multipleFixtures }
            let teams = try await database.read { try Team.fetchAll($0) }
            return ParsedMatchup(
              fixtures: fixtures, teams: teams,
              metadata: DescribedGameMetadata(fixture: fixtures[0], context: context)
            )
          }
          guard !Task.isCancelled else { return }
          await send(.parseResponse(revision, source, result))
        }
        .cancellable(id: CancelID.parse, cancelInFlight: true)

      case let .parseResponse(revision, source, .success(parsed)):
        guard revision == state.revision, source == state.source, !source.isEmpty else { return .none }
        state.isParsing = false
        state.parsedSource = source
        state.savedTeams = parsed.teams
        var review = FixtureTeamReview(fixtures: parsed.fixtures, savedTeams: parsed.teams)
        for entry in review.entries {
          // The setup uses the best available match. The user can correct it in place.
          if let candidate = entry.resolution.candidates.first {
            try? review.select(.existing(candidate.team.id), for: entry.id)
          } else {
            try? review.select(.proposed, for: entry.id)
          }
        }
        state.review = review
        updateProposals(state: &state)
        state.metadataNotices = parsed.metadata.notices
        return .send(.delegate(.populated(
          state.revision, state.team(for: .first), state.team(for: .second), parsed.metadata
        )))

      case let .parseResponse(revision, source, .failure(error)):
        guard revision == state.revision, source == state.source, !source.isEmpty else { return .none }
        state.isParsing = false
        state.errorMessage = message(for: error)
        if case let GameParserError.unavailable(availability) = error {
          state.availability = availability
        }
        return .none

      case .clearButtonTapped:
        return clear(state: &state)

      case .delegate:
        return .none
      }
    }
  }

  private func sourceChanged(state: inout State, immediately: Bool) -> Effect<Action> {
    if state.source.isEmpty {
      return clear(state: &state)
    }
    state.revision += 1
    state.errorMessage = nil
    state.isParsing = false
    state.isDebouncing = !immediately
    let parse: Effect<Action> = immediately ? .send(.parse) : .run { send in
      try await clock.sleep(for: .milliseconds(500))
      await send(.parse)
    }
    .cancellable(id: CancelID.debounce, cancelInFlight: true)
    return .concatenate(
      .merge(.cancel(id: CancelID.parse), .cancel(id: CancelID.debounce)),
      parse
    )
  }

  private func clear(state: inout State) -> Effect<Action> {
    let revision = state.revision + 1
    let availability = state.availability
    state = State()
    state.revision = revision
    state.availability = availability
    return .concatenate(
      .merge(.cancel(id: CancelID.parse), .cancel(id: CancelID.debounce)),
      .send(.delegate(.cleared(revision)))
    )
  }

  private func updateProposals(state: inout State) {
    let entries = state.review?.entries ?? []
    state.proposals = state.proposals.filter { key, _ in entries.contains { $0.id == key } }
    let palette = ColorPalette.options.map { $0.color.hex() }
    for entry in entries where state.proposals[entry.id] == nil {
      let usedColors = Set(state.proposals.values.map(\.colorHex))
      let choices = palette.filter { !usedColors.contains($0) }
      let color = random { choices.randomElement(using: &$0) } ?? palette[0]
      state.proposals[entry.id] = Team(id: uuid(), name: entry.name, colorHex: color)
    }
  }

  private nonisolated enum CancelID {
    case debounce
    case parse
  }

  private nonisolated enum ParsingError: Error { case multipleFixtures }

  private func message(for error: any Error) -> String {
    switch error {
    case ParsingError.multipleFixtures, GameParserError.outputTooLong:
      "Describe one matchup only. Batch import is not available yet."
    case let error as GameParserError:
      error.localizedDescription
    default:
      "Could not read the description. Edit it to try again, or set up the game manually."
    }
  }
}
