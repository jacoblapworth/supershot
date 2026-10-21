import AlarmClient
import ComposableArchitecture
import Styleguide
import SubscriptionClient

@Reducer
package struct WelcomeFeature {
  @ObservableState
  package struct State: Equatable {
    package init() {}
  }

  package enum Action {
    case getStartedButtonTapped
    case delegate(Delegate)

    package enum Delegate { case completed }
  }

  package var body: some Reducer<State, Action> {
    Reduce { _, action in
      switch action {
      case .getStartedButtonTapped:
        .send(.delegate(.completed))
      case .delegate:
        .none
      }
    }
  }

  package init() {}
}
