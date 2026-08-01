import ComposableArchitecture
import Foundation
import SQLiteData

@Reducer
struct TeamSlotFeature {
  nonisolated enum Mode: Equatable, Sendable {
    case creating
    case editing
    case empty
    case choosing
    case locked

    var isInteracting: Bool {
      self == .choosing || self == .creating || self == .editing
    }
  }

  nonisolated enum Side: Equatable, Hashable, Sendable {
    case left
    case right

    var defaultColorHex: String {
      self == .left ? TeamColorPalette.blue : TeamColorPalette.red
    }

    var title: String {
      self == .left ? "Left team" : "Right team"
    }
  }

  nonisolated struct TeamDraft: Equatable, Sendable {
    var colorHex: String
    var name = ""

    var trimmedName: String {
      Team.trimmedName(name)
    }
  }

  nonisolated enum Selection: Equatable, Sendable {
    case existing(original: Team, draft: TeamDraft)
    case new(TeamDraft)

    var draft: TeamDraft {
      switch self {
      case let .existing(_, draft), let .new(draft):
        draft
      }
    }

    var existingID: Team.ID? {
      guard case let .existing(original, _) = self else { return nil }
      return original.id
    }

    var hasSharedChanges: Bool {
      guard case let .existing(original, draft) = self else { return false }
      return original.name != draft.trimmedName || original.colorHex != draft.colorHex
    }

    func updating(_ draft: TeamDraft) -> Self {
      switch self {
      case let .existing(original, _):
        .existing(original: original, draft: draft)
      case .new:
        .new(draft)
      }
    }
  }

  @ObservableState
  struct State: Equatable {
    var editor: TeamDraft
    var mode = Mode.empty
    var searchText = ""
    var selection: Selection?
    let side: Side

    init(side: Side) {
      self.side = side
      self.editor = TeamDraft(colorHex: side.defaultColorHex)
    }

    var canFinishEditing: Bool {
      !editor.trimmedName.isEmpty && TeamColorPalette.isValid(editor.colorHex)
    }

    var isLocked: Bool {
      mode == .locked && selection != nil
    }

    var selectedDraft: TeamDraft? {
      selection?.draft
    }
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case cardTapped
    case changeTeamButtonTapped
    case createTeamButtonTapped
    case doneButtonTapped
    case editTeamButtonTapped
    case existingTeamSelected(Team)
    case paletteColorButtonTapped(String)
    case revertChangesButtonTapped
  }

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .cancelButtonTapped:
        switch state.mode {
        case .choosing:
          state.mode = state.selection == nil ? .empty : .locked
        case .creating:
          state.mode = .choosing
        case .editing:
          state.mode = .locked
        case .empty, .locked:
          break
        }
        return .none

      case .cardTapped:
        guard state.mode == .empty else { return .none }
        state.mode = .choosing
        state.searchText = ""
        return .none

      case .changeTeamButtonTapped:
        guard state.mode == .locked else { return .none }
        state.mode = .choosing
        state.searchText = ""
        return .none

      case .createTeamButtonTapped:
        guard state.mode == .choosing else { return .none }
        state.editor = TeamDraft(colorHex: state.side.defaultColorHex)
        state.mode = .creating
        return .none

      case .doneButtonTapped:
        guard state.canFinishEditing else { return .none }
        state.editor.name = state.editor.trimmedName
        switch state.mode {
        case .creating:
          state.selection = .new(state.editor)
          state.mode = .locked
        case .editing:
          state.selection = state.selection?.updating(state.editor)
          state.mode = .locked
        case .choosing, .empty, .locked:
          break
        }
        return .none

      case .editTeamButtonTapped:
        guard state.mode == .locked, let selection = state.selection else { return .none }
        state.editor = selection.draft
        state.mode = .editing
        return .none

      case let .existingTeamSelected(team):
        guard state.mode == .choosing else { return .none }
        let draft = TeamDraft(colorHex: team.colorHex, name: team.name)
        state.selection = .existing(original: team, draft: draft)
        state.mode = .locked
        state.searchText = ""
        return .none

      case let .paletteColorButtonTapped(colorHex):
        guard state.mode == .creating || state.mode == .editing else { return .none }
        guard TeamColorPalette.isValid(colorHex) else { return .none }
        state.editor.colorHex = colorHex.uppercased()
        return .none

      case .revertChangesButtonTapped:
        guard case let .existing(original, _) = state.selection else { return .none }
        state.selection = .existing(
          original: original,
          draft: TeamDraft(colorHex: original.colorHex, name: original.name)
        )
        return .none
      }
    }
  }
}

@Reducer
struct SetupFeature {
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

  @ObservableState
  struct State: Equatable {
    var availableTeams: [Team] = []
    @Presents var confirmationDialog: ConfirmationDialogState<ConfirmationDialogAction>?
    var customizesBreaks = false
    var didLoadTeams = false
    var errorMessage: String?
    var firstBreakDuration = DurationDraft(totalSeconds: 4 * 60)
    var firstCentrePass: TeamSide?
    var halfTimeDuration = DurationDraft(totalSeconds: 4 * 60)
    var isLoadingTeams = false
    var isSaving = false
    var leftTeam = TeamSlotFeature.State(side: .left)
    var periodDuration = DurationDraft(totalSeconds: 15 * 60)
    var rightTeam = TeamSlotFeature.State(side: .right)
    var secondBreakDuration = DurationDraft(totalSeconds: 4 * 60)

    var activeTeamSide: TeamSide? {
      if leftTeam.mode.isInteracting { return .teamA }
      if rightTeam.mode.isInteracting { return .teamB }
      return nil
    }

    var breakDurationsAreValid: Bool {
      firstBreakDuration.totalSeconds != nil
        && halfTimeDuration.totalSeconds != nil
        && secondBreakDuration.totalSeconds != nil
    }

    var canStartGame: Bool {
      leftTeam.isLocked
        && rightTeam.isLocked
        && activeTeamSide == nil
        && firstCentrePass != nil
        && hasUniqueTeamNames
        && (periodDuration.totalSeconds ?? 0) > 0
        && breakDurationsAreValid
        && !isLoadingTeams
        && !isSaving
    }

    var canSwapTeams: Bool {
      leftTeam.isLocked && rightTeam.isLocked && activeTeamSide == nil && !isSaving
    }

    var configurationSummary: String {
      let matchup: String
      if
        let leftName = leftTeam.selectedDraft?.trimmedName,
        let rightName = rightTeam.selectedDraft?.trimmedName,
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

    var hasSharedTeamChanges: Bool {
      leftTeam.selection?.hasSharedChanges == true
        || rightTeam.selection?.hasSharedChanges == true
    }

    var hasUniqueTeamNames: Bool {
      guard
        let leftSelection = leftTeam.selection,
        let rightSelection = rightTeam.selection,
        !leftSelection.draft.trimmedName.isEmpty,
        !rightSelection.draft.trimmedName.isEmpty
      else { return false }

      if
        let leftID = leftSelection.existingID,
        let rightID = rightSelection.existingID,
        leftID == rightID
      {
        return false
      }

      let selectedExistingIDs = Set(
        [leftSelection.existingID, rightSelection.existingID].compactMap { $0 }
      )
      var names = availableTeams
        .filter { !selectedExistingIDs.contains($0.id) }
        .map(\.normalizedName)
      names.append(Team.normalizeName(leftSelection.draft.name))
      names.append(Team.normalizeName(rightSelection.draft.name))
      return Set(names).count == names.count
    }

    var teamNameErrorMessage: String? {
      guard leftTeam.isLocked, rightTeam.isLocked else { return nil }
      guard
        let leftSelection = leftTeam.selection,
        let rightSelection = rightTeam.selection
      else { return nil }
      if leftSelection.draft.trimmedName.isEmpty || rightSelection.draft.trimmedName.isEmpty {
        return "Enter a name for both teams."
      }
      if leftSelection.existingID == rightSelection.existingID,
        leftSelection.existingID != nil
      {
        return "Choose two different teams."
      }
      return hasUniqueTeamNames ? nil : "Team names must be unique."
    }

    var teamUpdateMessage: String {
      [leftTeam.selection, rightTeam.selection]
        .compactMap { selection -> String? in
          guard
            let selection,
            case let .existing(original, draft) = selection,
            selection.hasSharedChanges
          else { return nil }
          if original.name == draft.trimmedName {
            return "\(original.name)'s color will update in game history."
          }
          return "\(original.name) will become \(draft.trimmedName) in game history."
        }
        .joined(separator: " ")
    }
  }

  enum Action: BindableAction {
    case allBreakPresetButtonTapped(Int)
    case binding(BindingAction<State>)
    case confirmationDialog(PresentationAction<ConfirmationDialogAction>)
    case customizeBreaksButtonTapped
    case delegate(Delegate)
    case firstBreakPresetButtonTapped(Int)
    case halfTimePresetButtonTapped(Int)
    case leftTeam(TeamSlotFeature.Action)
    case periodPresetButtonTapped(Int)
    case rightTeam(TeamSlotFeature.Action)
    case secondBreakPresetButtonTapped(Int)
    case startGameButtonTapped
    case startGameResponse(Result<ScoringFeature.State, any Error>)
    case swapTeamsButtonTapped
    case task
    case teamsResponse(Result<[Team], any Error>)
    case useFirstBreakForAllButtonTapped

    enum Delegate {
      case gameStarted(ScoringFeature.State)
    }
  }

  enum ConfirmationDialogAction: Equatable {
    case updateAndStartButtonTapped
  }

  private struct PreparedTeam: Sendable {
    let draft: TeamSlotFeature.TeamDraft
    let existingID: Team.ID?
    let id: Team.ID
  }

  @Dependency(\.date.now) var now
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    CombineReducers {
      BindingReducer()
      Scope(state: \.leftTeam, action: \.leftTeam) {
        TeamSlotFeature()
      }
      Scope(state: \.rightTeam, action: \.rightTeam) {
        TeamSlotFeature()
      }
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

        case .confirmationDialog(.dismiss):
          return .none

        case .confirmationDialog(.presented(.updateAndStartButtonTapped)):
          state.confirmationDialog = nil
          return beginStartingGame(state: &state)

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

        case .leftTeam(.createTeamButtonTapped), .leftTeam(.existingTeamSelected(_)):
          state.firstCentrePass = nil
          state.errorMessage = nil
          return .none

        case .leftTeam:
          state.errorMessage = nil
          return .none

        case let .periodPresetButtonTapped(seconds):
          state.periodDuration = DurationDraft(totalSeconds: seconds)
          return .none

        case .rightTeam(.createTeamButtonTapped), .rightTeam(.existingTeamSelected(_)):
          state.firstCentrePass = nil
          state.errorMessage = nil
          return .none

        case .rightTeam:
          state.errorMessage = nil
          return .none

        case let .secondBreakPresetButtonTapped(seconds):
          state.secondBreakDuration = DurationDraft(totalSeconds: seconds)
          return .none

        case .startGameButtonTapped:
          guard !state.isSaving else { return .none }
          guard state.leftTeam.isLocked, state.rightTeam.isLocked else {
            state.errorMessage = "Choose both teams."
            return .none
          }
          guard state.hasUniqueTeamNames else {
            state.errorMessage = state.teamNameErrorMessage ?? "Team names must be unique."
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

          if state.hasSharedTeamChanges {
            state.confirmationDialog = .confirmTeamUpdates(message: state.teamUpdateMessage)
            return .none
          }
          return beginStartingGame(state: &state)

        case let .startGameResponse(.success(scoring)):
          state.isSaving = false
          return .send(.delegate(.gameStarted(scoring)))

        case let .startGameResponse(.failure(error)):
          if case .duplicateTeamName = error as? SetupPersistenceError {
            state.errorMessage = "Team names must be unique."
          } else {
            state.errorMessage = "Could not start the game. Please choose the teams again."
          }
          state.isSaving = false
          return .none

        case .swapTeamsButtonTapped:
          guard state.canSwapTeams else { return .none }
          let leftSelection = state.leftTeam.selection
          state.leftTeam.selection = state.rightTeam.selection
          state.rightTeam.selection = leftSelection
          if state.firstCentrePass == .teamA {
            state.firstCentrePass = .teamB
          } else if state.firstCentrePass == .teamB {
            state.firstCentrePass = .teamA
          }
          return .none

        case .task:
          guard !state.didLoadTeams else { return .none }
          state.didLoadTeams = true
          state.isLoadingTeams = true
          return .run { send in
            let result = await Result {
              try await database.read { db in
                try Team.order { ($0.normalizedName, $0.id) }.fetchAll(db)
              }
            }
            await send(.teamsResponse(result))
          }

        case let .teamsResponse(.success(teams)):
          state.availableTeams = teams
          state.isLoadingTeams = false
          return .none

        case .teamsResponse(.failure):
          state.errorMessage = "Could not load saved teams."
          state.isLoadingTeams = false
          return .none

        case .useFirstBreakForAllButtonTapped:
          state.halfTimeDuration = state.firstBreakDuration
          state.secondBreakDuration = state.firstBreakDuration
          state.customizesBreaks = false
          return .none
        }
      }
    }
    .ifLet(\.$confirmationDialog, action: \.confirmationDialog)
  }

  private func beginStartingGame(state: inout State) -> Effect<Action> {
    guard
      let leftSelection = state.leftTeam.selection,
      let rightSelection = state.rightTeam.selection,
      let firstCentrePass = state.firstCentrePass,
      let periodDurationSeconds = state.periodDuration.totalSeconds,
      let firstBreakDurationSeconds = state.firstBreakDuration.totalSeconds,
      let halfTimeDurationSeconds = state.halfTimeDuration.totalSeconds,
      let secondBreakDurationSeconds = state.secondBreakDuration.totalSeconds
    else { return .none }

    let gameID = uuid()
    let teamA = PreparedTeam(
      draft: leftSelection.draft,
      existingID: leftSelection.existingID,
      id: leftSelection.existingID ?? uuid()
    )
    let teamB = PreparedTeam(
      draft: rightSelection.draft,
      existingID: rightSelection.existingID,
      id: rightSelection.existingID ?? uuid()
    )
    let centrePassTeamID = firstCentrePass == .teamA ? teamA.id : teamB.id
    let startedAt = now

    state.errorMessage = nil
    state.isSaving = true
    return startGameEffect(
      centrePassTeamID: centrePassTeamID,
      firstBreakDurationSeconds: firstBreakDurationSeconds,
      gameID: gameID,
      halfTimeDurationSeconds: halfTimeDurationSeconds,
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
    periodDurationSeconds: Int,
    secondBreakDurationSeconds: Int,
    startedAt: Date,
    teamA: PreparedTeam,
    teamB: PreparedTeam
  ) -> Effect<Action> {
    .run { send in
      let result = await Result {
        try await database.write { db in
          guard teamA.id != teamB.id else {
            throw SetupPersistenceError.duplicateTeamName
          }

          var finalTeams = try Team.fetchAll(db)
          let existingTeamIDs = Set(finalTeams.map(\.id))
          for existingID in [teamA.existingID, teamB.existingID].compactMap({ $0 }) {
            guard existingTeamIDs.contains(existingID) else {
              throw SetupPersistenceError.teamUnavailable
            }
          }
          let editedIDs = Set([teamA.existingID, teamB.existingID].compactMap { $0 })
          finalTeams.removeAll { editedIDs.contains($0.id) }
          finalTeams.append(Team(id: teamA.id, name: teamA.draft.name, colorHex: teamA.draft.colorHex))
          finalTeams.append(Team(id: teamB.id, name: teamB.draft.name, colorHex: teamB.draft.colorHex))
          let normalizedNames = finalTeams.map(\.normalizedName)
          guard Set(normalizedNames).count == normalizedNames.count else {
            throw SetupPersistenceError.duplicateTeamName
          }

          var occupiedNormalizedNames = Set(finalTeams.map(\.normalizedName))
          for (index, team) in [teamA, teamB].enumerated() where team.existingID != nil {
            var temporaryNormalizedName = "__supershot_pending__\(gameID.uuidString.lowercased())-\(index)"
            while occupiedNormalizedNames.contains(temporaryNormalizedName) {
              temporaryNormalizedName.append("_")
            }
            occupiedNormalizedNames.insert(temporaryNormalizedName)
            try Team.find(team.id).update {
              $0.normalizedName = #bind(temporaryNormalizedName)
            }
            .execute(db)
          }

          for team in [teamA, teamB] {
            let savedTeam = Team(
              id: team.id,
              name: team.draft.name,
              colorHex: team.draft.colorHex
            )
            if team.existingID != nil {
              try Team.find(team.id).update {
                $0.colorHex = #bind(savedTeam.colorHex)
                $0.name = #bind(savedTeam.name)
                $0.normalizedName = #bind(savedTeam.normalizedName)
              }
              .execute(db)
            } else {
              try Team.insert { savedTeam }.execute(db)
            }
          }

          try Game.insert {
            Game(
              id: gameID,
              startedAt: startedAt,
              endedAt: nil,
              teamAID: teamA.id,
              teamBID: teamB.id,
              centrePassTeamID: centrePassTeamID,
              periodDurationSeconds: periodDurationSeconds,
              firstBreakDurationSeconds: firstBreakDurationSeconds,
              halfTimeDurationSeconds: halfTimeDurationSeconds,
              secondBreakDurationSeconds: secondBreakDurationSeconds,
              isInBreak: false,
              isAwaitingCentrePassConfirmation: false,
              currentPeriod: 1,
              elapsedSeconds: 0,
              hasTimerStartedCurrentPeriod: false
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
            id: teamA.id,
            colorHex: teamA.draft.colorHex,
            name: teamA.draft.trimmedName
          ),
          teamB: ScoringFeature.Team(
            id: teamB.id,
            colorHex: teamB.draft.colorHex,
            name: teamB.draft.trimmedName
          )
        )
      }
      await send(.startGameResponse(result))
    }
  }
}

extension ConfirmationDialogState where Action == SetupFeature.ConfirmationDialogAction {
  static func confirmTeamUpdates(message: String) -> Self {
    Self {
      TextState("Update saved teams?")
    } actions: {
      ButtonState(action: .updateAndStartButtonTapped) {
        TextState("Update and start")
      }
      ButtonState(role: .cancel) {
        TextState("Cancel")
      }
    } message: {
      TextState(message)
    }
  }
}

private nonisolated enum SetupPersistenceError: Error {
  case duplicateTeamName
  case teamUnavailable
}
