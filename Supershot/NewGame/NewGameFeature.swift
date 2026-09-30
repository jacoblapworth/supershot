import SwiftUI
import ComposableArchitecture
import Foundation
import Sharing
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
    var bibColor: Color
    var team: Team?

    init(bibColor: Color) {
      self.bibColor = bibColor
    }
  }

  @ObservableState
  struct State: Equatable {
    var timing = SetupTiming()
    var customizesBreaks: Bool {
      get { timing.customizesBreaks }
      set { timing.customizesBreaks = newValue }
    }
    var errorMessage: String?
    var firstBreakDuration: DurationDraft {
      get { timing.firstBreakDuration }
      set { timing.firstBreakDuration = newValue }
    }
    var firstCentrePass: TeamSide = .teamA
    var halfTimeDuration: DurationDraft {
      get { timing.halfTimeDuration }
      set { timing.halfTimeDuration = newValue }
    }
    var isSaving = false
    var leftTeam = TeamSelection(bibColor: ColorPalette.blue)
    var location = LocationState.idle
    @Presents var teamConfiguration: SetupTeamFeature.State?
    @Presents var timingEditor: SetupTimingFeature.State?
    var configuringTeamSide: TeamSide?
    var pendingTeamConfiguration: TeamSide?
    @Presents var picker: TeamPickerFeature.State?
    var pickingTeamSide: TeamSide?
    var periodDuration: DurationDraft {
      get { timing.periodDuration }
      set { timing.periodDuration = newValue }
    }
    var rightTeam = TeamSelection(bibColor: ColorPalette.red)
    var secondBreakDuration: DurationDraft {
      get { timing.secondBreakDuration }
      set { timing.secondBreakDuration = newValue }
    }

    init() {
      @Shared(.defaultBreakDurationSeconds) var defaultBreakDurationSeconds
      @Shared(.defaultPeriodDurationSeconds) var defaultPeriodDurationSeconds

      let defaultBreak = DurationDraft(totalSeconds: defaultBreakDurationSeconds)
      firstBreakDuration = defaultBreak
      halfTimeDuration = defaultBreak
      periodDuration = DurationDraft(totalSeconds: defaultPeriodDurationSeconds)
      secondBreakDuration = defaultBreak
    }

    var breakDurationsAreValid: Bool {
      firstBreakDuration.totalSeconds != nil
        && halfTimeDuration.totalSeconds != nil
        && secondBreakDuration.totalSeconds != nil
    }

    var canStartGame: Bool {
      leftTeam.team != nil
        && rightTeam.team != nil
        && hasDifferentSelectedTeams
        && teamConfiguration?.isSaving != true
        && (periodDuration.totalSeconds ?? 0) > 0
        && breakDurationsAreValid
        && !isSaving
    }

    var canSwapTeams: Bool {
      leftTeam.team != nil && rightTeam.team != nil && picker == nil && teamConfiguration == nil && timingEditor == nil && !isSaving
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
      return "\(matchup)\(timing.summary)"
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
    case binding(BindingAction<State>)
    case delegate(Delegate)
    case locationButtonTapped
    case locationResponse(Result<GameLocation, any Error>)
    case picker(PresentationAction<TeamPickerFeature.Action>)
    case selectTeamButtonTapped(TeamSide)
    case startGameButtonTapped
    case startGameResponse(Result<ScoringFeature.State, any Error>)
    case swapTeamsButtonTapped
    case task
    case pickerDidDismiss
    case teamConfiguration(PresentationAction<SetupTeamFeature.Action>)
    case timingEditor(PresentationAction<SetupTimingFeature.Action>)
    case editTimingButtonTapped

    enum Delegate {
      case gameStarted(ScoringFeature.State)
    }
  }

  private struct PreparedTeam: Sendable {
    let bibColor: Color
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
        case .binding:
          state.errorMessage = nil
          if !state.customizesBreaks {
            state.halfTimeDuration = state.firstBreakDuration
            state.secondBreakDuration = state.firstBreakDuration
          }
          return .none

        case .delegate:
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
            state.leftTeam.bibColor = team.color
          case .teamB:
            state.rightTeam.team = team
            state.rightTeam.bibColor = team.color
          }
          state.pendingTeamConfiguration = pickingTeamSide
          state.picker = nil
          state.pickingTeamSide = nil
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

        case let .selectTeamButtonTapped(side):
          guard !state.isSaving else { return .none }
          let selectedTeam = side == .teamA ? state.leftTeam.team : state.rightTeam.team
          if let selectedTeam {
            state.configuringTeamSide = side
            state.teamConfiguration = SetupTeamFeature.State(
              team: selectedTeam,
              excluding: Set((side == .teamA ? state.rightTeam.team : state.leftTeam.team).map { [$0.id] } ?? [])
            )
            return .none
          }
          let excludedTeamIDs: Set<Team.ID>
          switch side {
          case .teamA:
            excludedTeamIDs = state.rightTeam.team.map { [$0.id] } ?? []
          case .teamB:
            excludedTeamIDs = state.leftTeam.team.map { [$0.id] } ?? []
          }
          state.pickingTeamSide = side
          state.picker = TeamPickerFeature.State(excluding: excludedTeamIDs)
          state.errorMessage = nil
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

        case .pickerDidDismiss:
          guard let side = state.pendingTeamConfiguration else { return .none }
          state.pendingTeamConfiguration = nil
          return .send(.selectTeamButtonTapped(side))

        case let .teamConfiguration(.presented(.delegate(.teamUpdated(team)))):
          guard let side = state.configuringTeamSide else { return .none }
          if side == .teamA {
            state.leftTeam.team = team
            state.leftTeam.bibColor = team.color
          } else {
            state.rightTeam.team = team
            state.rightTeam.bibColor = team.color
          }
          return .none

        case .teamConfiguration(.presented(.delegate(.done))):
          state.teamConfiguration = nil
          state.configuringTeamSide = nil
          return .none

        case .teamConfiguration(.dismiss):
          state.configuringTeamSide = nil
          return .none

        case .teamConfiguration:
          return .none

        case .editTimingButtonTapped:
          state.timingEditor = SetupTimingFeature.State(timing: state.timing)
          return .none

        case let .timingEditor(.presented(.delegate(.committed(timing)))):
          state.timing = timing
          state.timingEditor = nil
          state.errorMessage = nil
          return .none

        case .timingEditor(.presented(.delegate(.cancelled))):
          state.timingEditor = nil
          return .none

        case .timingEditor:
          return .none

        case .task:
          guard state.location == .idle else { return .none }
          return loadLocation(state: &state)

        }
    }
    .ifLet(\.$teamConfiguration, action: \.teamConfiguration) { SetupTeamFeature() }
    .ifLet(\.$timingEditor, action: \.timingEditor) { SetupTimingFeature() }
    .ifLet(\.$picker, action: \.picker) {
      TeamPickerFeature()
    }
  }

  private func beginStartingGame(state: inout State) -> Effect<Action> {
    guard
      let leftTeam = state.leftTeam.team,
      let rightTeam = state.rightTeam.team,
      let periodDurationSeconds = state.periodDuration.totalSeconds,
      let firstBreakDurationSeconds = state.firstBreakDuration.totalSeconds,
      let halfTimeDurationSeconds = state.halfTimeDuration.totalSeconds,
      let secondBreakDurationSeconds = state.secondBreakDuration.totalSeconds
    else { return .none }

    let gameID = uuid()
    let teamA = PreparedTeam(
      bibColor: state.leftTeam.bibColor,
      team: leftTeam
    )
    let teamB = PreparedTeam(
      bibColor: state.rightTeam.bibColor,
      team: rightTeam
    )
    let centrePassTeamID = state.firstCentrePass == .teamA ? teamA.team.id : teamB.team.id
    let breakDurations = [
      firstBreakDurationSeconds,
      halfTimeDurationSeconds,
      secondBreakDurationSeconds,
    ]
    let periods = (0..<4).map { position in
      GamePeriod(
        id: uuid(),
        gameID: gameID,
        position: position,
        durationSeconds: periodDurationSeconds,
        breakAfterDurationSeconds: breakDurations.indices.contains(position)
          ? breakDurations[position]
          : nil
      )
    }
    let startedAt = now
    let location = state.gameLocation

    state.errorMessage = nil
    state.isSaving = true
    return startGameEffect(
      centrePassTeamID: centrePassTeamID,
      gameID: gameID,
      location: location,
      periods: periods,
      startedAt: startedAt,
      teamA: teamA,
      teamB: teamB
    )
  }

  private func startGameEffect(
    centrePassTeamID: Team.ID,
    gameID: Game.ID,
    location: GameLocation?,
    periods: [GamePeriod],
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
              teamABibColorHex: teamA.bibColor.hex(),
              teamBID: teamB.team.id,
              teamBBibColorHex: teamB.bibColor.hex(),
              centrePassTeamID: centrePassTeamID,
              latitude: location?.latitude,
              longitude: location?.longitude,
              pointOfInterestName: location?.pointOfInterestName,
              isAwaitingCentrePassConfirmation: false,
              currentPhaseIndex: 0,
              elapsedSeconds: 0,
              timerEndsAt: nil
            )
          }
          .execute(db)
          try GamePeriod.insert { periods }.execute(db)
        }

        return ScoringFeature.State(
          centrePassTeamID: centrePassTeamID,
          gameID: gameID,
          periods: periods,
          startedAt: startedAt,
          teamA: ScoringFeature.Team(
            id: teamA.team.id,
            bibColor: teamA.bibColor,
            name: teamA.team.name
          ),
          teamB: ScoringFeature.Team(
            id: teamB.team.id,
            bibColor: teamB.bibColor,
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
