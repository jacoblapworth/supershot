import AppSettings
import ComposableArchitecture
import Database
import Foundation
import GameAnalysis
import GameCore
import GameServices
import LocationClient
import PermissionsFeature
import PreviewSupport
import SQLiteData
import ScoringFeature
import SharedModels
import Sharing
import Styleguide
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import WidgetSupport

@Reducer
package struct NewGameFeature {
  nonisolated package enum LocationState: Equatable, Sendable {
    case idle
    case requesting
    case denied
    case restricted
    case loaded(GameLocation)
    case loading
    case failed
  }

  nonisolated package enum TeamSide: Equatable, Hashable, Sendable {
    case teamA
    case teamB
  }

  nonisolated package struct DurationDraft: Equatable, Sendable {
    package var minutesText: String
    package var secondsText: String

    package init(totalSeconds: Int) {
      minutesText = String(max(totalSeconds, 0) / 60)
      secondsText = String(max(totalSeconds, 0) % 60)
    }

    package var formatted: String {
      guard let totalSeconds else { return "Invalid" }
      return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    package var totalSeconds: Int? {
      guard
        let minutes = Int(minutesText),
        let seconds = Int(secondsText),
        (0...99).contains(minutes),
        (0...59).contains(seconds)
      else { return nil }
      return minutes * 60 + seconds
    }
  }

  nonisolated package struct TeamSelection: Equatable, Sendable {
    package var bibColor: Color
    package var team: Team?

    package init(bibColor: Color) {
      self.bibColor = bibColor
    }
  }

  @ObservableState
  package struct State: Equatable {
    package var alarms = AlarmPermissionFeature.State()
    package var timing = SetupTiming()
    package var customizesBreaks: Bool {
      get { timing.customizesBreaks }
      set { timing.customizesBreaks = newValue }
    }
    package var errorMessage: String?
    package var firstBreakDuration: DurationDraft {
      get { timing.firstBreakDuration }
      set { timing.firstBreakDuration = newValue }
    }
    package var firstCentrePass: TeamSide = .teamA
    package var halfTimeDuration: DurationDraft {
      get { timing.halfTimeDuration }
      set { timing.halfTimeDuration = newValue }
    }
    package var isSaving = false
    package var leftTeam = TeamSelection(bibColor: ColorPalette.blue)
    package var location = LocationState.idle
    @Presents package var destination: NewGameDestination.State?
    package var pendingTeamConfiguration: NewGameTeamConfiguration.State?
    package var periodDuration: DurationDraft {
      get { timing.periodDuration }
      set { timing.periodDuration = newValue }
    }
    package var rightTeam = TeamSelection(bibColor: ColorPalette.red)
    package var secondBreakDuration: DurationDraft {
      get { timing.secondBreakDuration }
      set { timing.secondBreakDuration = newValue }
    }

    package init() {
      @Shared(.defaultBreakStartPolicy) var defaultBreakStartPolicy
      timing.breakStartPolicy = defaultBreakStartPolicy
      @Shared(.defaultBreakDurationSeconds) var defaultBreakDurationSeconds
      @Shared(.defaultPeriodDurationSeconds) var defaultPeriodDurationSeconds

      let defaultBreak = DurationDraft(totalSeconds: defaultBreakDurationSeconds)
      firstBreakDuration = defaultBreak
      halfTimeDuration = defaultBreak
      periodDuration = DurationDraft(totalSeconds: defaultPeriodDurationSeconds)
      secondBreakDuration = defaultBreak
    }

    package var breakDurationsAreValid: Bool {
      firstBreakDuration.totalSeconds != nil
        && halfTimeDuration.totalSeconds != nil
        && secondBreakDuration.totalSeconds != nil
    }

    package var canStartGame: Bool {
      leftTeam.team != nil
        && rightTeam.team != nil
        && hasDifferentSelectedTeams
        && !isSavingTeamConfiguration
        && (periodDuration.totalSeconds ?? 0) > 0
        && breakDurationsAreValid
        && !isSaving
    }

    package var canSwapTeams: Bool {
      leftTeam.team != nil && rightTeam.team != nil && destination == nil && !isSaving
    }

    package var configurationSummary: String {
      let matchup: String
      if let leftName = leftTeam.team?.name,
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

    package var hasDifferentSelectedTeams: Bool {
      guard let leftID = leftTeam.team?.id, let rightID = rightTeam.team?.id else { return false }
      return leftID != rightID
    }

    private var isSavingTeamConfiguration: Bool {
      guard case .teamConfiguration(let configuration) = destination else { return false }
      return configuration.configuration.isSaving
    }

    package var gameLocation: GameLocation? {
      guard case .loaded(let location) = location else { return nil }
      return location
    }

    package var teamNameErrorMessage: String? {
      guard leftTeam.team != nil, rightTeam.team != nil else { return nil }
      return hasDifferentSelectedTeams ? nil : "Choose two different teams."
    }
  }

  package enum Action: BindableAction {
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

    package enum Delegate {
      case gameStarted(ScoringFeature.State)
      case proPromotionTapped
    }
  }

  private struct PreparedTeam: Sendable {
    let bibColor: Color
    let team: Team
  }

  @Dependency(\.date.now) package var now
  @Dependency(\.defaultDatabase) package var database
  @Dependency(\.locationClient) package var locationClient
  @Dependency(\.uuid) package var uuid

  package var body: some Reducer<State, Action> {
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

      case .locationAuthorizationResponse(let status):
        return loadLocation(state: &state, authorization: status)

      case .sceneBecameActive:
        guard state.location != .loading, state.location != .requesting else { return .none }
        if case .loaded = state.location, locationClient.authorizationStatus() == .authorized {
          return .none
        }
        return loadLocation(state: &state)

      case .locationResponse(.success(let location)):
        state.location = .loaded(location)
        return .none

      case .locationResponse(.failure):
        state.location = .failed
        return .none

      case .destination(.presented(.teamPicker(.picker(.delegate(.teamSelected(let team)))))):
        guard case .teamPicker(let picker) = state.destination else { return .none }
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

      case .destination(
        .presented(.teamConfiguration(.configuration(.delegate(.teamUpdated(let team)))))
      ):
        guard case .teamConfiguration(let configuration) = state.destination else { return .none }
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

      case .destination(.presented(.timingEditor(.delegate(.committed(let timing))))):
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

      case .selectTeamButtonTapped(let side):
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

      case .startGameResponse(.success(let scoring)):
        state.isSaving = false
        return .send(.delegate(.gameStarted(scoring)))

      case .startGameResponse(.failure(let error)):
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
      breakStartPolicy: state.timing.breakStartPolicy,
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
    breakStartPolicy: BreakStartPolicy,
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
              timerEndsAt: nil,
              breakStartPolicy: breakStartPolicy
            )
          }
          .execute(db)
          try GamePeriod.insert { periods }.execute(db)
        }

        return await ScoringFeature.State(
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

  package init() {

  }
}

@Reducer
package enum NewGameDestination {
  case teamConfiguration(NewGameTeamConfiguration)
  case teamPicker(NewGameTeamPicker)
  case timingEditor(SetupTimingFeature)
}

extension NewGameDestination.State: Equatable {}

@Reducer
package struct NewGameTeamConfiguration {
  @ObservableState
  package struct State: Equatable {
    package var configuration: SetupTeamFeature.State
    package let side: NewGameFeature.TeamSide

    package init(configuration: SetupTeamFeature.State, side: NewGameFeature.TeamSide) {
      self.configuration = configuration
      self.side = side
    }
  }

  package enum Action {
    case configuration(SetupTeamFeature.Action)
  }

  package var body: some Reducer<State, Action> {
    Scope(state: \.configuration, action: \.configuration) {
      SetupTeamFeature()
    }
  }

  package init() {

  }
}

@Reducer
package struct NewGameTeamPicker {
  @ObservableState
  package struct State: Equatable {
    package var picker: TeamPickerFeature.State
    package let side: NewGameFeature.TeamSide

    package init(picker: TeamPickerFeature.State, side: NewGameFeature.TeamSide) {
      self.picker = picker
      self.side = side
    }
  }

  package enum Action {
    case picker(TeamPickerFeature.Action)
  }

  package var body: some Reducer<State, Action> {
    Scope(state: \.picker, action: \.picker) {
      TeamPickerFeature()
    }
  }

  package init() {

  }
}

private nonisolated enum SetupPersistenceError: Error {
  case duplicateTeam
  case teamUnavailable
}
