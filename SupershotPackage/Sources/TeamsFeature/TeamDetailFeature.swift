import ComposableArchitecture
import Database
import Foundation
import GameAnalysis
import GameCore
import GameDetailFeature
import GameServices
import NewGameFeature
import PaywallFeature
import PreviewSupport
import ScoringFeature
import SharedModels
import Styleguide
import SubscriptionClient
import TeamEditingFeature
import WidgetSupport

@Reducer
package struct TeamDetailFeature {
  @ObservableState
  package struct State: Equatable {
    @Presents package var editor: TeamEditorFeature.State?
    package let teamID: Team.ID

    package init(editor: TeamEditorFeature.State? = nil, teamID: Team.ID) {
      self.editor = editor
      self.teamID = teamID
    }
  }

  package enum Action {
    case deleteButtonTapped
    case delegate(Delegate)
    case editButtonTapped(Team)
    case editor(PresentationAction<TeamEditorFeature.Action>)
    case gameRowTapped(GameListItem)
    case newGameButtonTapped(Team)

    package enum Delegate: Equatable {
      case deleteTeamButtonTapped
      case gameRowTapped(GameListItem)
      case newGameButtonTapped(Team)
    }
  }

  package var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .deleteButtonTapped:
        return .send(.delegate(.deleteTeamButtonTapped))

      case .delegate:
        return .none

      case .editButtonTapped(let team):
        guard team.id == state.teamID else { return .none }
        state.editor = TeamEditorFeature.State(team: team)
        return .none

      case .editor(.presented(.delegate(.cancelled))),
        .editor(.presented(.delegate(.saved(_)))):
        state.editor = nil
        return .none

      case .editor:
        return .none

      case .gameRowTapped(let game):
        return .send(.delegate(.gameRowTapped(game)))

      case .newGameButtonTapped(let team):
        guard team.id == state.teamID else { return .none }
        return .send(.delegate(.newGameButtonTapped(team)))
      }
    }
    .ifLet(\.$editor, action: \.editor) {
      TeamEditorFeature()
    }
  }

  package init() {

  }
}
