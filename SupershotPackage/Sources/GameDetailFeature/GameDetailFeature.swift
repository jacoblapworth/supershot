import AppUI
import ComposableArchitecture
import Database
import Foundation
import GameAnalysis
import GameCore
import GameServices
import PreviewSupport
import SharedModels
import UI

@Reducer
package struct GameDetailFeature {
  @ObservableState
  package struct State: Equatable {
    package let gameID: Game.ID

    package init(gameID: Game.ID) {
      self.gameID = gameID
    }
  }

  package enum Action: Equatable {
    case deleteButtonTapped
    case delegate(Delegate)
    case viewAppeared

    package enum Delegate: Equatable {
      case deleteGameButtonTapped
    }
  }

  package var body: some Reducer<State, Action> {
    Reduce { _, action in
      switch action {
      case .deleteButtonTapped:
        .send(.delegate(.deleteGameButtonTapped))

      case .delegate, .viewAppeared:
        .none
      }
    }
  }

  package init() {}
}
