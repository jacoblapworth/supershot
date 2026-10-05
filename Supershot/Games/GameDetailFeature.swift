import ComposableArchitecture
import Foundation

@Reducer
struct GameDetailFeature {
  @ObservableState
  struct State: Equatable {
    let gameID: Game.ID
  }

  enum Action: Equatable {
    case deleteButtonTapped
    case delegate(Delegate)
    case viewAppeared

    enum Delegate: Equatable {
      case deleteGameButtonTapped
    }
  }

  var body: some Reducer<State, Action> {
    Reduce { _, action in
      switch action {
      case .deleteButtonTapped:
        return .send(.delegate(.deleteGameButtonTapped))

      case .delegate, .viewAppeared:
        return .none
      }
    }
  }
}
