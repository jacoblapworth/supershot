import SwiftUI
import ComposableArchitecture
import Foundation
import Sharing
import SQLiteData



@Reducer
struct NewGameFeature {
  nonisolated enum LocationState: Equatable, Sendable {
    case idle
    case requesting
    case denied
    case restricted
    case loaded(GameLocation)
    case loading
    case failed
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
    var alarms = AlarmPermissionFeature.State()
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
    @Presents var destination: NewGameDestination.State?
    var pendingTeamConfiguration: NewGameTeamConfiguration.State?
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
        && !isSavingTeamConfiguration
        && (periodDuration.totalSeconds ?? 0) > 0
        && breakDurationsAreValid
        && !isSaving
    }

    var canSwapTeams: Bool {
      leftTeam.team != nil && rightTeam.team != nil && destination == nil && !isSaving
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

    private var isSavingTeamConfiguration: Bool {
      guard case let .teamConfiguration(configuration) = destination else { return false }
      return configuration.configuration.isSaving
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
    case alarms(AlarmPermissionFeature.Action)
    case binding(BindingAction<State>)
    case delegate(Delegate)
    case destination(PresentationAction<NewGameDestination.Action>)
    case destinationDidDismiss
    case editTimingButtonTapped
    case locationButtonTapped
    case locationAuthorizationResponse(LocationAuthorizationStatus)
    case sceneBecameActive
    case locationResponse(Result<GameLocation, any Error>)
    case selectTeamButtonTapped(TeamSide)
    case startGameButtonTapped
    case startGameResponse(Result<ScoringFeature.State, any Error>)
    case swapTeamsButtonTapped
    case task

    enum Delegate {
      case gameStarted(ScoringFeature.State)
      case proPromotionTapped
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
    Scope(state: \.alarms, action: \.alarms) { AlarmPermissionFeature() }
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

        case .alarms(.delegate(.proPromotionTapped)):
          return .send(.delegate(.proPromotionTapped))

        case .alarms:
          return .none

        case .delegate:
          return .none

        case .locationButtonTapped:
          guard state.location != .loading, state.location != .requesting else { return .none }
          if locationClient.authorizationStatus() == .notDetermined {
            state.location = .requesting
            return .run { send in
              await send(.locationAuthorizationResponse(await locationClient.requestAuthorization()))
            }
            .cancellable(id: CancelID.location, cancelInFlight: true)
          }
          return loadLocation(state: &state)

        case let .locationAuthorizationResponse(status):
          return loadLocation(state: &state, authorization: status)

        case .sceneBecameActive:
          guard state.location != .loading, state.location != .requesting else { return .none }
          if case .loaded = state.location, locationClient.authorizationStatus() == .authorized {
            return .none
          }
          return loadLocation(state: &state)

        case let .locationResponse(.success(location)):
          state.location = .loaded(location)
          return .none

        case .locationResponse(.failure):
          state.location = .failed
          return .none

        case let .destination(.presented(.teamPicker(.picker(.delegate(.teamSelected(team)))))):
          guard case let .teamPicker(picker) = state.destination else { return .none }
          switch picker.side {
          case .teamA:
            state.leftTeam.team = team
            state.leftTeam.bibColor = team.color
          case .teamB:
            state.rightTeam.team = team
            state.rightTeam.bibColor = team.color
          }
          state.pendingTeamConfiguration = NewGameTeamConfiguration.State(
            configuration: SetupTeamFeature.State(
              team: team,
              excluding: excludedTeamIDs(for: picker.side, state: state)
            ),
            side: picker.side
          )
          state.destination = nil
          state.errorMessage = nil
          return .none

        case .destination(.presented(.teamPicker(.picker(.delegate(.cancelled))))):
          state.destination = nil
          return .none

        case let .destination(
          .presented(.teamConfiguration(.configuration(.delegate(.teamUpdated(team)))))
        ):
          guard case let .teamConfiguration(configuration) = state.destination else { return .none }
          if configuration.side == .teamA {
            state.leftTeam.team = team
            state.leftTeam.bibColor = team.color
          } else {
            state.rightTeam.team = team
            state.rightTeam.bibColor = team.color
          }
          return .none

        case .destination(.presented(.teamConfiguration(.configuration(.delegate(.done))))):
          state.destination = nil
          return .none

        case let .destination(.presented(.timingEditor(.delegate(.committed(timing))))):
          state.timing = timing
          state.destination = nil
          state.errorMessage = nil
          return .none

        case .destination(.presented(.timingEditor(.delegate(.cancelled)))):
          state.destination = nil
          return .none

        case .destination:
          return .none

        case .destinationDidDismiss:
          guard let pendingTeamConfiguration = state.pendingTeamConfiguration else { return .none }
          state.pendingTeamConfiguration = nil
          state.destination = .teamConfiguration(pendingTeamConfiguration)
          return .none

        case .editTimingButtonTapped:
          state.destination = .timingEditor(SetupTimingFeature.State(timing: state.timing))
          return .none

        case let .selectTeamButtonTapped(side):
          guard !state.isSaving else { return .none }
          let selectedTeam = side == .teamA ? state.leftTeam.team : state.rightTeam.team
          if let selectedTeam {
            state.destination = .teamConfiguration(
              NewGameTeamConfiguration.State(
                configuration: SetupTeamFeature.State(
                  team: selectedTeam,
                  excluding: excludedTeamIDs(for: side, state: state)
                ),
                side: side
              )
            )
            return .none
          }
          state.destination = .teamPicker(
            NewGameTeamPicker.State(
              picker: TeamPickerFeature.State(excluding: excludedTeamIDs(for: side, state: state)),
              side: side
            )
          )
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

        case .task:
          guard state.location == .idle else { return .none }
          return loadLocation(state: &state)

        }
    }
    .ifLet(\.$destination, action: \.destination) {
      NewGameDestination.body
    }
  }

  private func excludedTeamIDs(for side: TeamSide, state: State) -> Set<Team.ID> {
    switch side {
    case .teamA:
      return state.rightTeam.team.map { [$0.id] } ?? []
    case .teamB:
      return state.leftTeam.team.map { [$0.id] } ?? []
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

  private func loadLocation(
    state: inout State,
    authorization: LocationAuthorizationStatus? = nil
  ) -> Effect<Action> {
    switch authorization ?? locationClient.authorizationStatus() {
    case .notDetermined:
      state.location = .idle
      return .none
    case .denied:
      state.location = .denied
      return .none
    case .restricted:
      state.location = .restricted
      return .none
    case .authorized:
      break
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

@Reducer
enum NewGameDestination {
  case teamConfiguration(NewGameTeamConfiguration)
  case teamPicker(NewGameTeamPicker)
  case timingEditor(SetupTimingFeature)
}

extension NewGameDestination.State: Equatable {}

@Reducer
struct NewGameTeamConfiguration {
  @ObservableState
  struct State: Equatable {
    var configuration: SetupTeamFeature.State
    let side: NewGameFeature.TeamSide
  }

  enum Action {
    case configuration(SetupTeamFeature.Action)
  }

  var body: some Reducer<State, Action> {
    Scope(state: \.configuration, action: \.configuration) {
      SetupTeamFeature()
    }
  }
}

@Reducer
struct NewGameTeamPicker {
  @ObservableState
  struct State: Equatable {
    var picker: TeamPickerFeature.State
    let side: NewGameFeature.TeamSide
  }

  enum Action {
    case picker(TeamPickerFeature.Action)
  }

  var body: some Reducer<State, Action> {
    Scope(state: \.picker, action: \.picker) {
      TeamPickerFeature()
    }
  }
}

private nonisolated enum SetupPersistenceError: Error {
  case duplicateTeam
  case teamUnavailable
}
