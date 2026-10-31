import AppUI
import ComposableArchitecture
import Database
import Foundation
import GameCore
import PreviewSupport
import SharedModels
import SQLiteData
import SwiftUI
import UI

@Reducer
package struct TeamPickerFeature {
  @ObservableState
  package struct State: Equatable {
    package var availableTeams: [Team] = []
    package var didLoadTeams = false
    @Presents package var editor: TeamEditorFeature.State?
    package var errorMessage: String?
    package var excludedTeamIDs: Set<Team.ID>
    package var isLoadingTeams = false
    package var searchText = ""
    package var proposedTeam: Team?

    package init(excluding excludedTeamIDs: Set<Team.ID> = [], proposedTeam: Team? = nil) {
      self.excludedTeamIDs = excludedTeamIDs
      self.proposedTeam = proposedTeam
      searchText = proposedTeam?.name ?? ""
    }

    package var filteredTeams: [Team] {
      let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      return availableTeams.filter { team in
        !excludedTeamIDs.contains(team.id)
          && (query.isEmpty
            || team.name.range(
              of: query,
              options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil)
      }
    }
  }

  package enum Action: BindableAction {
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case createTeamButtonTapped
    case delegate(Delegate)
    case editor(PresentationAction<TeamEditorFeature.Action>)
    case task
    case teamSelected(Team)
    case teamsResponse(Result<[Team], any Error>)

    package enum Delegate: Equatable {
      case cancelled
      case teamSelected(Team)
    }
  }

  @Dependency(\.defaultDatabase) package var database

  package var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        state.errorMessage = nil
        return .none

      case .cancelButtonTapped:
        return .send(.delegate(.cancelled))

      case .createTeamButtonTapped:
        var editor = TeamEditorFeature.State()
        editor.name = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let proposedTeam = state.proposedTeam {
          editor.color = proposedTeam.color
        }
        state.editor = editor
        return .none

      case .delegate:
        return .none

      case .editor(.presented(.delegate(.cancelled))):
        state.editor = nil
        return .none

      case let .editor(.presented(.delegate(.saved(team)))):
        state.editor = nil
        return .send(.delegate(.teamSelected(team)))

      case .editor:
        return .none

      case .task:
        guard !state.didLoadTeams else { return .none }
        state.didLoadTeams = true
        state.isLoadingTeams = true
        return .run { send in
          let result = await Result {
            try await database.read { db in
              try Team.order { ($0.name, $0.id) }.fetchAll(db)
            }
          }
          await send(.teamsResponse(result))
        }

      case let .teamSelected(team):
        guard !state.excludedTeamIDs.contains(team.id) else { return .none }
        return .send(.delegate(.teamSelected(team)))

      case let .teamsResponse(.success(teams)):
        state.availableTeams = teams
        state.isLoadingTeams = false
        return .none

      case .teamsResponse(.failure):
        state.isLoadingTeams = false
        state.errorMessage = "Could not load saved teams."
        return .none
      }
    }
    .ifLet(\.$editor, action: \.editor) {
      TeamEditorFeature()
    }
  }

  package init() {}
}
