import ComposableArchitecture
import SQLiteData
import SwiftUI

@Reducer
struct SetupTeamFeature {
  @ObservableState
  struct State: Equatable {
    var draft: Team.Draft
    var errorMessage: String?
    var excludedTeamIDs: Set<Team.ID>
    var failedColorHex: String?
    var isSaving = false
    @Presents var picker: TeamPickerFeature.State?
    var savedTeam: Team

    init(team: Team, excluding excludedTeamIDs: Set<Team.ID> = []) {
      draft = Team.Draft(team)
      savedTeam = team
      self.excludedTeamIDs = excludedTeamIDs
    }

    var previewTeam: Team {
      var team = savedTeam
      team.colorHex = draft.colorHex
      return team
    }
  }

  enum Action {
    case changeTeamButtonTapped
    case colorChanged(Color)
    case delegate(Delegate)
    case doneButtonTapped
    case picker(PresentationAction<TeamPickerFeature.Action>)
    case retryButtonTapped
    case saveResponse(Result<Team, any Error>)

    @CasePathable
    enum Delegate {
      case done
      case teamUpdated(Team)
    }
  }

  @Dependency(\.defaultDatabase) var database

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .changeTeamButtonTapped:
        guard !state.isSaving else { return .none }
        state.picker = TeamPickerFeature.State(excluding: state.excludedTeamIDs)
        return .none
      case let .colorChanged(color):
        state.draft.colorHex = color.hex()
        state.errorMessage = nil
        state.failedColorHex = nil
        let preview = state.previewTeam
        let save = state.isSaving ? Effect<Action>.none : saveColor(state: &state)
        return .concatenate(.send(.delegate(.teamUpdated(preview))), save)
      case .delegate:
        return .none
      case .doneButtonTapped:
        guard !state.isSaving else { return .none }
        return .send(.delegate(.done))
      case let .picker(.presented(.delegate(.teamSelected(team)))):
        state.savedTeam = team
        state.draft = Team.Draft(team)
        state.errorMessage = nil
        state.failedColorHex = nil
        state.picker = nil
        return .send(.delegate(.teamUpdated(team)))
      case .picker(.presented(.delegate(.cancelled))):
        state.picker = nil
        return .none
      case .picker:
        return .none
      case .retryButtonTapped:
        guard !state.isSaving, let colorHex = state.failedColorHex else { return .none }
        return .send(.colorChanged(Color(hex: colorHex)))
      case let .saveResponse(.success(team)):
        state.savedTeam = team
        state.isSaving = false
        if state.draft.colorHex != team.colorHex {
          return saveColor(state: &state)
        }
        return .send(.delegate(.teamUpdated(team)))
      case .saveResponse(.failure):
        state.isSaving = false
        state.failedColorHex = state.draft.colorHex
        state.draft = Team.Draft(state.savedTeam)
        state.errorMessage = "Couldn’t save bib colour. Try again."
        return .send(.delegate(.teamUpdated(state.savedTeam)))
      }
    }
    .ifLet(\.$picker, action: \.picker) { TeamPickerFeature() }
  }

  private func saveColor(state: inout State) -> Effect<Action> {
    guard state.draft.colorHex != state.savedTeam.colorHex else { return .none }
    state.isSaving = true
    let team = state.previewTeam
    return .run { send in
      let result = await Result {
        try await database.write { db in
          guard var current = try Team.find(team.id).fetchOne(db) else {
            throw SaveError.teamUnavailable
          }
          try Team.find(team.id).update { $0.colorHex = #bind(team.colorHex) }.execute(db)
          current.colorHex = team.colorHex
          return current
        }
      }
      await send(.saveResponse(result))
    }
  }

  private enum SaveError: Error { case teamUnavailable }
}

extension Team.Draft: Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id && lhs.name == rhs.name && lhs.colorHex == rhs.colorHex
  }
}
