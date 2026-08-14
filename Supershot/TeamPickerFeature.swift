import ComposableArchitecture
import Foundation
import SQLiteData

@Reducer
struct TeamPickerFeature {
  @ObservableState
  struct State: Equatable {
    var availableTeams: [Team] = []
    var didLoadTeams = false
    @Presents var editor: TeamEditorFeature.State?
    var errorMessage: String?
    var excludedTeamIDs: Set<Team.ID>
    var isLoadingTeams = false
    var searchText = ""

    init(excluding excludedTeamIDs: Set<Team.ID> = []) {
      self.excludedTeamIDs = excludedTeamIDs
    }

    var filteredTeams: [Team] {
      let query = Team.trimmedName(searchText)
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

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case createTeamButtonTapped
    case delegate(Delegate)
    case editor(PresentationAction<TeamEditorFeature.Action>)
    case task
    case teamSelected(Team)
    case teamsResponse(Result<[Team], any Error>)

    enum Delegate: Equatable {
      case cancelled
      case teamSelected(Team)
    }
  }

  @Dependency(\.defaultDatabase) var database

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        state.errorMessage = nil
        return .none

      case .cancelButtonTapped:
        return .send(.delegate(.cancelled))

      case .createTeamButtonTapped:
        state.editor = TeamEditorFeature.State()
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
}
