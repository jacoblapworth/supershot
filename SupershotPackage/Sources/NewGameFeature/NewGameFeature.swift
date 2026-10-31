import AppSettings
import AppUI
import ComposableArchitecture
import Database
import Foundation
import GameAnalysis
import GameCore
import GameServices
import LocationClient
import PermissionsFeature
import PreviewSupport
import ScoringFeature
import SharedModels
import Sharing
import SQLiteData
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import UI

@Reducer
package struct NewGameFeature {
  package typealias LocationState = SetupLocationStatus

  package nonisolated enum DescriptionField: Hashable, Sendable {
    case firstTeam
    case secondTeam
    case scheduledAt
    case court
    case division
  }

  package nonisolated enum TeamSide: Equatable, Hashable, Sendable {
    case teamA
    case teamB
  }

  package nonisolated struct DurationDraft: Equatable, Sendable {
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
        (0 ... 99).contains(minutes),
        (0 ... 59).contains(seconds)
      else { return nil }
      return minutes * 60 + seconds
    }
  }

  package nonisolated struct TeamSelection: Equatable, Sendable {
    package var bibColor: Color
    package var team: Team?

    package init(bibColor: Color) {
      self.bibColor = bibColor
    }
  }

  @ObservableState
  package struct State: Equatable {
    package var describeGame = DescribeGameFeature.State()
    package var gameID: Game.ID
    package var createdAt: Date
    package var periodIDs: [GamePeriod.ID]
    package var scheduledAt: Date?
    package var scheduled: Bool {
      get { scheduledAt != nil }
      set {
        @Dependency(\.date.now) var now
        scheduledAt = newValue ? (scheduledAt ?? now) : nil
      }
    }

    package var court = ""
    package var division = ""
    package var parsedFields: Set<DescriptionField> = []
    package var requiresExistingGame = false
    package var lastSavedDraft: GameSetupDraft?
    package var inFlightDraft: GameSetupDraft?
    package var pendingSaveIntent: SaveIntent?
    package var failedSaveIntent: SaveIntent?
    package var closesAfterSave = false
    package var hasEnteredScoring = false
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
    package var currentLocation: GameLocation?
    package var selectedLocation: GameLocation?
    package var preservesLocationSelection = false
    package var locationRequestID = 0
    package var nearbyPlaces: [NearbyPlace] = []
    package var nearbyPlacesStatus = NearbyPlacesStatus.idle
    @Presents package var destination: NewGameDestination.State?
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
      @Dependency(\.uuid) var uuid
      @Dependency(\.date.now) var now
      gameID = uuid()
      createdAt = now
      periodIDs = (0 ..< 4).map { _ in uuid() }
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

    package init(snapshot: GameSnapshot) {
      self.init()
      gameID = snapshot.game.id
      createdAt = snapshot.game.createdAt
      periodIDs = snapshot.periods.map(\.id)
      requiresExistingGame = true
      preservesLocationSelection = true
      scheduledAt = snapshot.game.scheduledAt
      court = snapshot.game.court ?? ""
      division = snapshot.game.division ?? ""
      leftTeam.team = snapshot.teamA
      leftTeam.bibColor = snapshot.game.teamABibColor
      rightTeam.team = snapshot.teamB
      rightTeam.bibColor = snapshot.game.teamBBibColor
      firstCentrePass = snapshot.game.centrePassTeamID == snapshot.teamB.id ? .teamB : .teamA
      timing.breakStartPolicy = snapshot.game.breakStartPolicy
      if let first = snapshot.periods.first {
        periodDuration = .init(totalSeconds: first.durationSeconds)
      }
      let breaks = snapshot.periods.dropLast().map { $0.breakAfterDurationSeconds ?? 0 }
      firstBreakDuration = .init(totalSeconds: breaks.first ?? 0)
      halfTimeDuration = .init(totalSeconds: breaks.dropFirst().first ?? 0)
      secondBreakDuration = .init(totalSeconds: breaks.dropFirst(2).first ?? 0)
      customizesBreaks = Set(breaks).count > 1
      if let location = snapshot.game.location {
        self.location = .loaded
        selectedLocation = location
      }
      lastSavedDraft = draft
    }

    /// Only committed setup values are included; temporary child-editor edits stay transient.
    package var draft: GameSetupDraft? {
      guard !describeGame.isBusy,
            let teamA = leftTeam.team, let teamB = rightTeam.team,
            teamA.id != teamB.id, timing.isValid, periodIDs.count == 4
      else { return nil }
      let court = court.trimmingCharacters(in: .whitespacesAndNewlines)
      let division = division.trimmingCharacters(in: .whitespacesAndNewlines)
      let breaks = [firstBreakDuration, halfTimeDuration, secondBreakDuration]
      return GameSetupDraft(
        game: Game(
          id: gameID,
          startedAt: nil,
          teamAID: teamA.id,
          teamABibColorHex: leftTeam.bibColor.hex(),
          teamBID: teamB.id,
          teamBBibColorHex: rightTeam.bibColor.hex(),
          centrePassTeamID: firstCentrePass == .teamA ? teamA.id : teamB.id,
          latitude: gameLocation?.latitude,
          longitude: gameLocation?.longitude,
          pointOfInterestName: gameLocation?.pointOfInterestName,
          breakStartPolicy: timing.breakStartPolicy,
          createdAt: createdAt,
          scheduledAt: scheduledAt,
          court: court.isEmpty ? nil : court,
          division: division.isEmpty ? nil : division
        ),
        periods: periodIDs.enumerated().map { position, id in
          GamePeriod(
            id: id,
            gameID: gameID,
            position: position,
            durationSeconds: periodDuration.totalSeconds!,
            breakAfterDurationSeconds: position < breaks.count ? breaks[position].totalSeconds : nil
          )
        },
        teamsToCreate: describeGame.pendingTeams.filter { $0.id == teamA.id || $0.id == teamB.id }
      )
    }

    package var breakDurationsAreValid: Bool {
      firstBreakDuration.totalSeconds != nil
        && halfTimeDuration.totalSeconds != nil
        && secondBreakDuration.totalSeconds != nil
    }

    package var canPrepareScoring: Bool {
      leftTeam.team != nil
        && rightTeam.team != nil
        && hasDifferentSelectedTeams
        && !describeGame.isBusy
        && !isSavingTeamConfiguration
        && (periodDuration.totalSeconds ?? 0) > 0
        && breakDurationsAreValid
        && !isSaving
    }

    package var canSwapTeams: Bool {
      leftTeam.team != nil && rightTeam.team != nil && destination == nil && !isSaving
        && !describeGame.isBusy
    }

    package var configurationSummary: String {
      let matchup = if let leftName = leftTeam.team?.name,
                       let rightName = rightTeam.team?.name,
                       !leftName.isEmpty,
                       !rightName.isEmpty
      {
        "\(leftName) vs \(rightName) · "
      } else {
        ""
      }
      return "\(matchup)\(timing.summary)"
    }

    package var hasDifferentSelectedTeams: Bool {
      guard let leftID = leftTeam.team?.id, let rightID = rightTeam.team?.id else { return false }
      return leftID != rightID
    }

    private var isSavingTeamConfiguration: Bool {
      guard case let .teamConfiguration(configuration) = destination else { return false }
      return configuration.configuration.isSaving
    }

    package var gameLocation: GameLocation? {
      selectedLocation
    }

    package var teamNameErrorMessage: String? {
      guard leftTeam.team != nil, rightTeam.team != nil else { return nil }
      return hasDifferentSelectedTeams ? nil : "Choose two different teams."
    }
  }

  package nonisolated enum SaveIntent: Equatable, Sendable {
    case autosave
    case close
    case score
  }

  package enum Action: BindableAction {
    case alarms(AlarmPermissionFeature.Action)
    case binding(BindingAction<State>)
    case closeButtonTapped
    case configurationChanged
    case sceneBecameInactive
    case saveGameButtonTapped
    case retrySaveButtonTapped
    case plannedGameResponse(Result<GameSnapshot, any Error>)
    case describeGame(DescribeGameFeature.Action)
    case delegate(Delegate)
    case destination(PresentationAction<NewGameDestination.Action>)
    case editTimingButtonTapped
    case locationButtonTapped
    case locationAuthorizationResponse(LocationAuthorizationStatus)
    case sceneBecameActive
    case locationResponse(Int, Result<GameLocation, any Error>)
    case nearbyPlacesResponse(Int, Result<[NearbyPlace], any Error>)
    case changeLocationButtonTapped
    case selectTeamButtonTapped(TeamSide)
    case prepareScoringButtonTapped
    case prepareScoringResponse(Result<ScoringFeature.State, any Error>)
    case swapTeamsButtonTapped
    case task

    package enum Delegate {
      case scoringPrepared(ScoringFeature.State)
      case gameSaved
      case proPromotionTapped
    }
  }

  @Dependency(\.date.now) package var now
  @Dependency(\.defaultDatabase) package var database
  @Dependency(\.locationClient) package var locationClient

  package var body: some Reducer<State, Action> {
    Scope(state: \.describeGame, action: \.describeGame) { DescribeGameFeature() }
    Scope(state: \.alarms, action: \.alarms) { AlarmPermissionFeature() }
    BindingReducer()
    Reduce { state, action in
      switch action {
      case let .describeGame(.delegate(.populated(revision, first, second, metadata))):
        guard revision == state.describeGame.revision else { return .none }
        applyDescribedTeams(first, second, state: &state)
        if metadata.scheduledAt != nil || state.parsedFields.contains(.scheduledAt) {
          state.scheduledAt = metadata.scheduledAt
          state.parsedFields.insert(.scheduledAt)
        }
        if metadata.court != nil || state.parsedFields.contains(.court) {
          state.court = metadata.court ?? ""
          state.parsedFields.insert(.court)
        }
        if metadata.division != nil || state.parsedFields.contains(.division) {
          state.division = metadata.division ?? ""
          state.parsedFields.insert(.division)
        }
        state.errorMessage = nil
        return .none

      case let .describeGame(.delegate(.cleared(revision))):
        guard revision == state.describeGame.revision else { return .none }
        if state.parsedFields.contains(.firstTeam) {
          state.leftTeam = TeamSelection(bibColor: ColorPalette.blue)
        }
        if state.parsedFields.contains(.secondTeam) {
          state.rightTeam = TeamSelection(bibColor: ColorPalette.red)
        }
        if state.parsedFields.contains(.scheduledAt) {
          state.scheduledAt = nil
        }
        if state.parsedFields.contains(.court) {
          state.court = ""
        }
        if state.parsedFields.contains(.division) {
          state.division = ""
        }
        state.parsedFields = []
        state.errorMessage = nil
        return .none

      case .describeGame:
        return .none

      case .configurationChanged, .sceneBecameInactive:
        guard state.describeGame.source.isEmpty,
              !state.hasEnteredScoring, state.draft != state.lastSavedDraft else { return .none }
        return save(state: &state, intent: .autosave)

      case .closeButtonTapped:
        guard state.describeGame.source.isEmpty else { return .send(.delegate(.gameSaved)) }
        return save(state: &state, intent: .close)

      case .saveGameButtonTapped:
        return save(state: &state, intent: .close)

      case .retrySaveButtonTapped:
        return save(state: &state, intent: state.failedSaveIntent ?? .autosave)

      case .plannedGameResponse(.success):
        state.isSaving = false
        state.requiresExistingGame = true
        state.lastSavedDraft = state.inFlightDraft
        state.inFlightDraft = nil
        let intent = state.pendingSaveIntent ?? (state.closesAfterSave ? .close : .autosave)
        state.pendingSaveIntent = nil
        return save(state: &state, intent: intent)

      case .plannedGameResponse(.failure):
        state.closesAfterSave = state.closesAfterSave || state.pendingSaveIntent == .close
        state.failedSaveIntent = state.closesAfterSave ? .close : .autosave
        state.isSaving = false
        state.inFlightDraft = nil
        state.pendingSaveIntent = nil
        state.errorMessage = "Could not save the game. Your changes are still here. Try again."
        return .none

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
          updateLocationPicker(state: &state)
          return .run { send in
            await send(.locationAuthorizationResponse(locationClient.requestAuthorization()))
          }
          .cancellable(id: CancelID.location, cancelInFlight: true)
        }
        return loadLocation(state: &state)

      case let .locationAuthorizationResponse(status):
        return loadLocation(state: &state, authorization: status)

      case .sceneBecameActive:
        guard state.location != .loading, state.location != .requesting else { return .none }
        if state.currentLocation != nil, state.location == .loaded, locationClient.authorizationStatus() == .authorized {
          return .none
        }
        return loadLocation(state: &state)

      case .changeLocationButtonTapped:
        state.destination = .locationPicker(locationPickerState(state))
        if state.currentLocation == nil {
          guard state.location != .loading, state.location != .requesting else { return .none }
          return loadLocation(state: &state)
        }
        if state.nearbyPlacesStatus == .failed {
          return loadNearbyPlaces(state: &state)
        }
        return .none

      case let .locationResponse(requestID, result):
        guard requestID == state.locationRequestID else { return .none }
        switch result {
        case let .success(location):
          state.location = .loaded
          state.currentLocation = location
          if !state.preservesLocationSelection {
            state.selectedLocation = location
          }
          return loadNearbyPlaces(state: &state)
        case .failure:
          state.location = .failed
          updateLocationPicker(state: &state)
          return .none
        }

      case let .nearbyPlacesResponse(requestID, result):
        guard requestID == state.locationRequestID else { return .none }
        switch result {
        case let .success(places):
          state.nearbyPlaces = places
          state.nearbyPlacesStatus = .loaded
          if !state.preservesLocationSelection, let nearest = places.first {
            state.selectedLocation = nearest.location
          }
        case .failure:
          state.nearbyPlacesStatus = .failed
        }
        updateLocationPicker(state: &state)
        return .none

      case let .destination(.presented(.locationPicker(.placeTapped(id)))):
        guard let place = state.nearbyPlaces.first(where: { $0.id == id }) else { return .none }
        state.selectedLocation = place.location
        state.preservesLocationSelection = true
        state.destination = nil
        return .none

      case .destination(.presented(.locationPicker(.currentLocationTapped))):
        guard let location = state.currentLocation else { return .none }
        state.selectedLocation = location
        state.preservesLocationSelection = true
        state.destination = nil
        return .none

      case .destination(.presented(.locationPicker(.retryButtonTapped))):
        if state.currentLocation != nil, state.location == .loaded {
          return loadNearbyPlaces(state: &state)
        }
        return loadLocation(state: &state)

      case .destination(.presented(.locationPicker(.closeButtonTapped))):
        state.destination = nil
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
        state.destination = nil
        state.errorMessage = nil
        return .none

      case .destination(.presented(.teamPicker(.picker(.delegate(.cancelled))))):
        state.destination = nil
        return .none

      case let .destination(.presented(.teamConfiguration(.configuration(.delegate(.teamUpdated(team)))))):
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

      case .editTimingButtonTapped:
        state.destination = .timingEditor(SetupTimingFeature.State(timing: state.timing))
        return .none

      case let .selectTeamButtonTapped(side):
        guard !state.isSaving, !state.describeGame.isBusy else { return .none }
        let selectedTeam = side == .teamA ? state.leftTeam.team : state.rightTeam.team
        let proposal = selectedTeam.flatMap { selected in
          state.describeGame.pendingTeams.first { $0.id == selected.id }
        }
        if let selectedTeam, proposal == nil {
          state.destination = .teamConfiguration(NewGameTeamConfiguration.State(
            configuration: SetupTeamFeature.State(
              team: selectedTeam,
              excluding: excludedTeamIDs(for: side, state: state)
            ),
            side: side
          ))
          return .none
        }
        state.destination = .teamPicker(NewGameTeamPicker.State(
          picker: TeamPickerFeature.State(excluding: excludedTeamIDs(for: side, state: state), proposedTeam: proposal),
          side: side
        ))
        state.errorMessage = nil
        return .none

      case .prepareScoringButtonTapped:
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

        return save(state: &state, intent: .score)

      case let .prepareScoringResponse(.success(scoring)):
        state.hasEnteredScoring = true
        state.inFlightDraft = nil
        state.isSaving = false
        return .send(.delegate(.scoringPrepared(scoring)))

      case .prepareScoringResponse(.failure):
        state.failedSaveIntent = .score
        state.errorMessage = "Could not prepare scoring. Your changes are still here. Try again."
        state.isSaving = false
        state.inFlightDraft = nil
        return .none

      case .swapTeamsButtonTapped:
        guard state.canSwapTeams else { return .none }
        let firstWasParsed = state.parsedFields.remove(.firstTeam) != nil
        let secondWasParsed = state.parsedFields.remove(.secondTeam) != nil
        if firstWasParsed {
          state.parsedFields.insert(.secondTeam)
        }
        if secondWasParsed {
          state.parsedFields.insert(.firstTeam)
        }
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
        guard state.currentLocation == nil, state.location == .idle || state.location == .loaded else {
          return .none
        }
        return loadLocation(state: &state)
      }
    }
    .ifLet(\.$destination, action: \.destination) {
      NewGameDestination.body
    }
  }

  private func applyDescribedTeams(_ first: Team?, _ second: Team?, state: inout State) {
    if let first {
      state.leftTeam.team = first
      state.leftTeam.bibColor = first.color
      state.parsedFields.insert(.firstTeam)
    } else if state.parsedFields.contains(.firstTeam) {
      state.leftTeam = TeamSelection(bibColor: ColorPalette.blue)
    }
    if let second {
      state.rightTeam.team = second
      state.rightTeam.bibColor = second.color
      state.parsedFields.insert(.secondTeam)
    } else if state.parsedFields.contains(.secondTeam) {
      state.rightTeam = TeamSelection(bibColor: ColorPalette.red)
    }
  }

  private func excludedTeamIDs(for side: TeamSide, state: State) -> Set<Team.ID> {
    switch side {
    case .teamA:
      state.rightTeam.team.map { [$0.id] } ?? []
    case .teamB:
      state.leftTeam.team.map { [$0.id] } ?? []
    }
  }

  private func save(state: inout State, intent: SaveIntent) -> Effect<Action> {
    guard !state.hasEnteredScoring else { return .none }
    if state.isSaving {
      if intent != .autosave {
        state.pendingSaveIntent = intent
      }
      return .none
    }
    guard let draft = state.draft else {
      return intent == .close ? .send(.delegate(.gameSaved)) : .none
    }
    if intent != .score, draft == state.lastSavedDraft {
      return intent == .close ? .send(.delegate(.gameSaved)) : .none
    }
    state.closesAfterSave = intent == .close
    state.failedSaveIntent = nil
    state.errorMessage = nil
    state.isSaving = true
    state.inFlightDraft = draft
    let requiresExistingGame = state.requiresExistingGame
    return .run { send in
      let result = await Result {
        try await database.write { db in
          try draft.save(db, requiresExistingGame: requiresExistingGame)
        }
      }
      if intent == .score {
        switch result {
        case let .success(snapshot):
          await send(.prepareScoringResponse(.success(ScoringFeature.State(snapshot: snapshot))))
        case let .failure(error):
          await send(.prepareScoringResponse(.failure(error)))
        }
      } else {
        await send(.plannedGameResponse(result))
      }
    }
  }

  private func locationPickerState(_ state: State) -> SetupLocationPickerFeature.State {
    .init(
      currentLocation: state.currentLocation,
      selectedLocation: state.selectedLocation,
      places: state.nearbyPlaces,
      status: state.nearbyPlacesStatus,
      locationStatus: state.location
    )
  }

  private func updateLocationPicker(state: inout State) {
    guard case .locationPicker = state.destination else { return }
    state.destination = .locationPicker(locationPickerState(state))
  }

  private func loadNearbyPlaces(state: inout State) -> Effect<Action> {
    guard let location = state.currentLocation else { return .none }
    state.locationRequestID += 1
    let requestID = state.locationRequestID
    state.nearbyPlacesStatus = .loading
    updateLocationPicker(state: &state)
    return .run { send in
      let result = await Result { try await locationClient.nearbyPlaces(location) }
      guard !Task.isCancelled else { return }
      await send(.nearbyPlacesResponse(requestID, result))
    }
    .cancellable(id: CancelID.nearbyPlaces, cancelInFlight: true)
  }

  private func loadLocation(
    state: inout State,
    authorization: LocationAuthorizationStatus? = nil
  ) -> Effect<Action> {
    let invalidatesRequest = state.location == .loading || state.nearbyPlacesStatus == .loading
    state.nearbyPlacesStatus = .idle
    switch authorization ?? locationClient.authorizationStatus() {
    case .notDetermined:
      state.location = .idle
    case .denied:
      state.location = .denied
    case .restricted:
      state.location = .restricted
    case .authorized:
      state.location = .loading
    }
    if state.location == .loading || invalidatesRequest {
      state.locationRequestID += 1
    }
    updateLocationPicker(state: &state)
    let cancelSearch = Effect<Action>.cancel(id: CancelID.nearbyPlaces)
    guard state.location == .loading else {
      return .merge(cancelSearch, .cancel(id: CancelID.location))
    }
    let requestID = state.locationRequestID
    return .merge(
      cancelSearch,
      .run { send in
        let result = await Result { try await locationClient.currentLocation() }
        guard !Task.isCancelled else { return }
        await send(.locationResponse(requestID, result))
      }
      .cancellable(id: CancelID.location, cancelInFlight: true)
    )
  }

  private nonisolated enum CancelID {
    case location
    case nearbyPlaces
  }

  package init() {}
}

@Reducer
package enum NewGameDestination {
  case locationPicker(SetupLocationPickerFeature)
  case teamConfiguration(NewGameTeamConfiguration)
  case teamPicker(NewGameTeamPicker)
  case timingEditor(SetupTimingFeature)

  /// The synthesized conformance does not infer the reducer's main-actor isolation.
  @CasePathable
  @dynamicMemberLookup
  @ObservableState
  package enum State: @MainActor CaseReducerState {
    package typealias StateReducer = NewGameDestination
    case locationPicker(SetupLocationPickerFeature.State)
    case teamConfiguration(NewGameTeamConfiguration.State)
    case teamPicker(NewGameTeamPicker.State)
    case timingEditor(SetupTimingFeature.State)
  }
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

  package init() {}
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

  package init() {}
}
