import ComposableArchitecture
import Foundation

@Reducer
struct GameDetailFeature {
  @ObservableState
  struct State: Equatable {
    let gameID: Game.ID
  }

  enum Action {
    case viewAppeared
  }

  var body: some Reducer<State, Action> {
    Reduce { _, action in
      switch action {
      case .viewAppeared:
        return .none
      }
    }
  }
}
