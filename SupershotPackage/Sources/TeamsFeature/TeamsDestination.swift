import ComposableArchitecture
import Database
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
package enum TeamsDestination {
  case alert(AlertState<TeamsFeature.Alert>)
  case teamEditor(TeamsEditorFeature)
}

extension TeamsDestination.State: Equatable {}

/// Owns presentations above the team editor without discarding its draft.
@Reducer
package struct TeamsEditorFeature {
  @ObservableState
  package struct State: Equatable {
    @Presents package var alert: AlertState<TeamsFeature.Alert>?
    package var editor = TeamEditorFeature.State()

    package init(
      alert: AlertState<TeamsFeature.Alert>? = nil,
      editor: TeamEditorFeature.State = TeamEditorFeature.State()
    ) {
      self.alert = alert
      self.editor = editor
    }
  }

  package enum Action {
    case alert(PresentationAction<TeamsFeature.Alert>)
    case editor(TeamEditorFeature.Action)
  }

  package var body: some Reducer<State, Action> {
    Scope(state: \.editor, action: \.editor) {
      TeamEditorFeature()
    }
    .ifLet(\.$alert, action: \.alert)
  }

  package init() {

  }
}
