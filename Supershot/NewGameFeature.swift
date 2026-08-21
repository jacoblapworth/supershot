import ComposableArchitecture
import Foundation
import SQLiteData



@Reducer
struct NewGameFeature {
  nonisolated enum LocationState: Equatable, Sendable {
    case idle
    case loaded(GameLocation)
    case loading
    case unavailable(canRetry: Bool)
  }

  nonisolated enum TeamSide: Equatable, Hashable, Sendable {
    case teamA
    case teamB
  }

  nonisolated struct DurationDraft: Equatable, Sendable {
    var minutesText: String
    var secondsText: String

    init(totalSeconds: Int) {
      minutesText = String(max(totalSeconds, 0) / 60)
      secondsText = String(max(totalSeconds, 0) % 60)
    }

    var formatted: String {
      guard let totalSeconds else { return "Invalid" }
      return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    var totalSeconds: Int? {
      guard
        let minutes = Int(minutesText),
        let seconds = Int(secondsText),
        (0...99).contains(minutes),
        (0...59).contains(seconds)
      else { return nil }
      return minutes * 60 + seconds
    }
  }

  nonisolated struct TeamSelection: Equatable, Sendable {
    var bibColorHex: String
    var team: Team?

    init(bibColorHex: String) {
      self.bibColorHex = bibColorHex
    }
  }

  @ObservableState
  struct State: Equatable {
    var customizesBreaks = false
    var errorMessage: String?
    var firstBreakDuration = DurationDraft(totalSeconds: 1 * 60)
    var firstCentrePass: TeamSide?
    var halfTimeDuration = DurationDraft(totalSeconds: 1 * 60)
    var isSaving = false
    var leftTeam = TeamSelection(bibColorHex: TeamColorPalette.blue)
    var location = LocationState.idle
    @Presents var picker: TeamPickerFeature.State?
    var pickingTeamSide: TeamSide?
    var periodDuration = DurationDraft(totalSeconds: 8 * 60)
    var rightTeam = TeamSelection(bibColorHex: TeamColorPalette.red)
    var secondBreakDuration = DurationDraft(totalSeconds: 1 * 60)

    var breakDurationsAreValid: Bool {
      firstBreakDuration.totalSeconds != nil
        && halfTimeDuration.totalSeconds != nil
        && secondBreakDuration.totalSeconds != nil
    }

    var canStartGame: Bool {
      leftTeam.team != nil
        && rightTeam.team != nil
        && TeamColorPalette.isValid(leftTeam.bibColorHex)
        && TeamColorPalette.isValid(rightTeam.bibColorHex)
        && firstCentrePass != nil
        && (periodDuration.totalSeconds ?? 0) > 0
        && breakDurationsAreValid
        && !isSaving
    }

    var canSwapTeams: Bool {
      leftTeam.team != nil && rightTeam.team != nil && picker == nil && !isSaving
    }

    var configurationSummary: String {
      let matchup: String
      if
        let leftName = leftTeam.team?.name,
        let rightName = rightTeam.team?.name,
        !leftName.isEmpty,
        !rightName.isEmpty
      {
        matchup = "\(leftName) vs \(rightName) · "
      } else {
        matchup = ""
      }
      let quarter = periodDuration.formatted
      let breaks = [
        firstBreakDuration.formatted,
        halfTimeDuration.formatted,
        secondBreakDuration.formatted,
      ]
      if Set(breaks).count == 1, let first = breaks.first {
        return "\(matchup)4 × \(quarter) · \(first) breaks"
      }
      return "\(matchup)4 × \(quarter) · breaks \(breaks.joined(separator: " / "))"
    }

    var hasDifferentSelectedTeams: Bool {
      guard let leftID = leftTeam.team?.id, let rightID = rightTeam.team?.id else { return false }
      return leftID != rightID
    }

    var gameLocation: GameLocation? {
      guard case let .loaded(location) = location else { return nil }
      return location
    }

    var teamNameErrorMessage: String? {
      guard leftTeam.team != nil, rightTeam.team != nil else { return nil }
      return hasDifferentSelectedTeams ? nil : "Choose two different teams."
    }
  }

  enum Action: BindableAction {
    case allBreakPresetButtonTapped(Int)
    case binding(BindingAction<State>)
    case customizeBreaksButtonTapped
    case delegate(Delegate)
    case firstBreakPresetButtonTapped(Int)
    case halfTimePresetButtonTapped(Int)
    case locationButtonTapped
    case locationResponse(Result<GameLocation, any Error>)
    case periodPresetButtonTapped(Int)
    case picker(PresentationAction<TeamPickerFeature.Action>)
    case selectTeamButtonTapped(TeamSide)
    case secondBreakPresetButtonTapped(Int)
    case startGameButtonTapped
    case startGameResponse(Result<ScoringFeature.State, any Error>)
    case swapTeamsButtonTapped
    case task
    case useFirstBreakForAllButtonTapped

    enum Delegate {
      case gameStarted(ScoringFeature.State)
    }
  }

  private struct PreparedTeam: Sendable {
    let bibColorHex: String
    let team: Team
  }

  @Dependency(\.date.now) var now
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.locationClient) var locationClient
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
        switch action {
        case let .allBreakPresetButtonTapped(seconds):
          let duration = DurationDraft(totalSeconds: seconds)
          state.firstBreakDuration = duration
          state.halfTimeDuration = duration
          state.secondBreakDuration = duration
          return .none

        case .binding:
          state.errorMessage = nil
          if !state.customizesBreaks {
            state.halfTimeDuration = state.firstBreakDuration
            state.secondBreakDuration = state.firstBreakDuration
          }
          return .none

        case .customizeBreaksButtonTapped:
          state.customizesBreaks = true
          return .none

        case .delegate:
          return .none

        case let .firstBreakPresetButtonTapped(seconds):
          state.firstBreakDuration = DurationDraft(totalSeconds: seconds)
          return .none

        case let .halfTimePresetButtonTapped(seconds):
          state.halfTimeDuration = DurationDraft(totalSeconds: seconds)
          return .none

        case .locationButtonTapped:
          guard state.location != .loading else { return .none }
          return loadLocation(state: &state)

        case let .locationResponse(.success(location)):
          state.location = .loaded(location)
          return .none

        case .locationResponse(.failure):
          state.location = .unavailable(canRetry: true)
          return .none

        case let .picker(.presented(.delegate(.teamSelected(team)))):
          guard let pickingTeamSide = state.pickingTeamSide else { return .none }
          switch pickingTeamSide {
          case .teamA:
            state.leftTeam.team = team
            state.leftTeam.bibColorHex = team.colorHex
          case .teamB:
            state.rightTeam.team = team
            state.rightTeam.bibColorHex = team.colorHex
          }
          state.picker = nil
          state.pickingTeamSide = nil
          state.firstCentrePass = nil
          state.errorMessage = nil
          return .none

        case .picker(.presented(.delegate(.cancelled))):
          state.picker = nil
          state.pickingTeamSide = nil
          return .none

        case .picker(.dismiss):
          state.picker = nil
          state.pickingTeamSide = nil
          return .none

        case .picker:
          return .none

        case let .periodPresetButtonTapped(seconds):
          state.periodDuration = DurationDraft(totalSeconds: seconds)
          return .none

        case let .selectTeamButtonTapped(side):
          guard !state.isSaving else { return .none }
          let excludedTeamIDs: Set<Team.ID>
          switch side {
          case .teamA:
            excludedTeamIDs = state.rightTeam.team.map { [$0.id] } ?? []
          case .teamB:
            excludedTeamIDs = state.leftTeam.team.map { [$0.id] } ?? []
          }
          state.pickingTeamSide = side
          state.picker = TeamPickerFeature.State(excluding: excludedTeamIDs)
          state.firstCentrePass = nil
          state.errorMessage = nil
          return .none

        case let .secondBreakPresetButtonTapped(seconds):
          state.secondBreakDuration = DurationDraft(totalSeconds: seconds)
          return .none

        case .startGameButtonTapped:
          guard !state.isSaving else { return .none }
          guard state.leftTeam.team != nil, state.rightTeam.team != nil else {
            state.errorMessage = "Choose both teams."
            return .none
          }
          guard state.hasDifferentSelectedTeams else {
            state.errorMessage = state.teamNameErrorMessage ?? "Choose two different teams."
            return .none
          }
          guard
            TeamColorPalette.isValid(state.leftTeam.bibColorHex),
            TeamColorPalette.isValid(state.rightTeam.bibColorHex)
          else {
            state.errorMessage = "Choose a valid bib color for both teams."
            return .none
          }
          guard state.firstCentrePass != nil else {
            state.errorMessage = "Choose the team taking the first centre pass."
            return .none
          }
          guard (state.periodDuration.totalSeconds ?? 0) > 0, state.breakDurationsAreValid else {
            state.errorMessage = "Enter valid quarter and break durations."
            return .none
          }

          return beginStartingGame(state: &state)

        case let .startGameResponse(.success(scoring)):
          state.isSaving = false
          return .send(.delegate(.gameStarted(scoring)))

        case let .startGameResponse(.failure(error)):
          if case .duplicateTeam = error as? SetupPersistenceError {
            state.errorMessage = "Choose two different teams."
          } else {
            state.errorMessage = "Could not start the game. Please choose the teams again."
          }
          state.isSaving = false
          return .none

        case .swapTeamsButtonTapped:
          guard state.canSwapTeams else { return .none }
          let leftTeam = state.leftTeam
          state.leftTeam = state.rightTeam
          state.rightTeam = leftTeam
          if state.firstCentrePass == .teamA {
            state.firstCentrePass = .teamB
          } else if state.firstCentrePass == .teamB {
            state.firstCentrePass = .teamA
          }
          return .none

        case .task:
          guard state.location == .idle else { return .none }
          return loadLocation(state: &state)

        case .useFirstBreakForAllButtonTapped:
          state.halfTimeDuration = state.firstBreakDuration
          state.secondBreakDuration = state.firstBreakDuration
          state.customizesBreaks = false
          return .none
        }
    }
    .ifLet(\.$picker, action: \.picker) {
      TeamPickerFeature()
    }
  }

  private func beginStartingGame(state: inout State) -> Effect<Action> {
    guard
      let leftTeam = state.leftTeam.team,
      let rightTeam = state.rightTeam.team,
      let firstCentrePass = state.firstCentrePass,
      let periodDurationSeconds = state.periodDuration.totalSeconds,
      let firstBreakDurationSeconds = state.firstBreakDuration.totalSeconds,
      let halfTimeDurationSeconds = state.halfTimeDuration.totalSeconds,
      let secondBreakDurationSeconds = state.secondBreakDuration.totalSeconds
    else { return .none }

    let gameID = uuid()
    let teamA = PreparedTeam(
      bibColorHex: state.leftTeam.bibColorHex,
      team: leftTeam
    )
    let teamB = PreparedTeam(
      bibColorHex: state.rightTeam.bibColorHex,
      team: rightTeam
    )
    let centrePassTeamID = firstCentrePass == .teamA ? teamA.team.id : teamB.team.id
    let startedAt = now
    let location = state.gameLocation

    state.errorMessage = nil
    state.isSaving = true
    return startGameEffect(
      centrePassTeamID: centrePassTeamID,
      firstBreakDurationSeconds: firstBreakDurationSeconds,
      gameID: gameID,
      halfTimeDurationSeconds: halfTimeDurationSeconds,
      location: location,
      periodDurationSeconds: periodDurationSeconds,
      secondBreakDurationSeconds: secondBreakDurationSeconds,
      startedAt: startedAt,
      teamA: teamA,
      teamB: teamB
    )
  }

  private func startGameEffect(
    centrePassTeamID: Team.ID,
    firstBreakDurationSeconds: Int,
    gameID: Game.ID,
    halfTimeDurationSeconds: Int,
    location: GameLocation?,
    periodDurationSeconds: Int,
    secondBreakDurationSeconds: Int,
    startedAt: Date,
    teamA: PreparedTeam,
    teamB: PreparedTeam
  ) -> Effect<Action> {
    .run { send in
      let result = await Result {
        try await database.write { db in
          guard teamA.team.id != teamB.team.id else {
            throw SetupPersistenceError.duplicateTeam
          }

          let finalTeams = try Team.fetchAll(db)
          let existingTeamIDs = Set(finalTeams.map(\.id))
          for team in [teamA.team, teamB.team] {
            guard existingTeamIDs.contains(team.id) else {
              throw SetupPersistenceError.teamUnavailable
            }
          }

          try Game.insert {
            Game(
              id: gameID,
              startedAt: startedAt,
              endedAt: nil,
              teamAID: teamA.team.id,
              teamABibColorHex: teamA.bibColorHex,
              teamBID: teamB.team.id,
              teamBBibColorHex: teamB.bibColorHex,
              centrePassTeamID: centrePassTeamID,
              latitude: location?.latitude,
              longitude: location?.longitude,
              pointOfInterestName: location?.pointOfInterestName,
              periodDurationSeconds: periodDurationSeconds,
              firstBreakDurationSeconds: firstBreakDurationSeconds,
              halfTimeDurationSeconds: halfTimeDurationSeconds,
              secondBreakDurationSeconds: secondBreakDurationSeconds,
              isAwaitingCentrePassConfirmation: false,
              currentPhaseIndex: 0,
              elapsedSeconds: 0,
              timerEndsAt: nil
            )
          }
          .execute(db)
        }

        return ScoringFeature.State(
          centrePassTeamID: centrePassTeamID,
          firstBreakDurationSeconds: firstBreakDurationSeconds,
          gameID: gameID,
          halfTimeDurationSeconds: halfTimeDurationSeconds,
          periodDurationSeconds: periodDurationSeconds,
          secondBreakDurationSeconds: secondBreakDurationSeconds,
          startedAt: startedAt,
          teamA: ScoringFeature.Team(
            id: teamA.team.id,
            bibColorHex: teamA.bibColorHex,
            name: teamA.team.name
          ),
          teamB: ScoringFeature.Team(
            id: teamB.team.id,
            bibColorHex: teamB.bibColorHex,
            name: teamB.team.name
          )
        )
      }
      await send(.startGameResponse(result))
    }
  }

  private func loadLocation(state: inout State) -> Effect<Action> {
    guard locationClient.authorizationStatus() == .authorized else {
      state.location = .unavailable(canRetry: false)
      return .none
    }
    state.location = .loading
    return .run { send in
      await send(
        .locationResponse(
          await Result {
            try await locationClient.currentLocation()
          }
        )
      )
    }
    .cancellable(id: CancelID.location, cancelInFlight: true)
  }

  private nonisolated enum CancelID {
    case location
  }
}

private nonisolated enum SetupPersistenceError: Error {
  case duplicateTeam
  case teamUnavailable
}
