import ComposableArchitecture
import Foundation

@Reducer
struct TeamDetailFeature {
  @ObservableState
  struct State: Equatable {
    @Presents var editor: TeamEditorFeature.State?
    let teamID: Team.ID
  }

  enum Action {
    case deleteButtonTapped
    case delegate(Delegate)
    case editButtonTapped(Team)
    case editor(PresentationAction<TeamEditorFeature.Action>)
    case gameRowTapped(GameListItem)
    case newGameButtonTapped(Team)

    enum Delegate: Equatable {
      case deleteTeamButtonTapped
      case gameRowTapped(GameListItem)
      case newGameButtonTapped(Team)
    }
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .deleteButtonTapped:
        return .send(.delegate(.deleteTeamButtonTapped))

      case .delegate:
        return .none

      case let .editButtonTapped(team):
        guard team.id == state.teamID else { return .none }
        state.editor = TeamEditorFeature.State(team: team)
        return .none

      case .editor(.presented(.delegate(.cancelled))),
        .editor(.presented(.delegate(.saved(_)))):
        state.editor = nil
        return .none

      case .editor:
        return .none

      case let .gameRowTapped(game):
        return .send(.delegate(.gameRowTapped(game)))

      case let .newGameButtonTapped(team):
        guard team.id == state.teamID else { return .none }
        return .send(.delegate(.newGameButtonTapped(team)))
      }
    }
    .ifLet(\.$editor, action: \.editor) {
      TeamEditorFeature()
    }
  }
}
