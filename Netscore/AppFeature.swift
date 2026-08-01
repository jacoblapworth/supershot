import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {
  @ObservableState
  struct State: Equatable {
    var scoring: ScoringFeature.State?
    var setup = SetupFeature.State()
    var summary: SummaryFeature.State?
  }

  enum Action {
    case scoring(ScoringFeature.Action)
    case setup(SetupFeature.Action)
    case summary(SummaryFeature.Action)
  }

  var body: some Reducer<State, Action> {
    CombineReducers {
      Scope(state: \.setup, action: \.setup) {
        SetupFeature()
      }
      Reduce { state, action in
        switch action {
        case let .scoring(.delegate(.gameFinished(summary))):
          state.scoring = nil
          state.summary = summary
          return .none

        case .setup(.delegate(.gameStarted(let scoring))):
          state.scoring = scoring
          state.summary = nil
          return .none

        case .summary(.newGameButtonTapped):
          state.setup = SetupFeature.State()
          state.summary = nil
          return .none

        case .scoring, .setup, .summary:
          return .none
        }
      }
    }
    .ifLet(\.scoring, action: \.scoring) {
      ScoringFeature()
    }
    .ifLet(\.summary, action: \.summary) {
      SummaryFeature()
    }
  }
}
