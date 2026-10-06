import ComposableArchitecture

@Reducer
enum TeamsDestination {
  case alert(AlertState<TeamsFeature.Alert>)
  case teamEditor(TeamsEditorFeature)
}

extension TeamsDestination.State: Equatable {}

/// Owns presentations above the team editor without discarding its draft.
@Reducer
struct TeamsEditorFeature {
  @ObservableState
  struct State: Equatable {
    @Presents var alert: AlertState<TeamsFeature.Alert>?
    var editor = TeamEditorFeature.State()
  }

  enum Action {
    case alert(PresentationAction<TeamsFeature.Alert>)
    case editor(TeamEditorFeature.Action)
  }

  var body: some Reducer<State, Action> {
    Scope(state: \.editor, action: \.editor) {
      TeamEditorFeature()
    }
    .ifLet(\.$alert, action: \.alert)
  }
}
