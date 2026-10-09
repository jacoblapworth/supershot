import ComposableArchitecture

@Reducer
struct WelcomeFeature {
  @ObservableState
  struct State: Equatable {}

  enum Action {
    case getStartedButtonTapped
    case delegate(Delegate)

    enum Delegate { case completed }
  }

  var body: some Reducer<State, Action> {
    Reduce { _, action in
      switch action {
      case .getStartedButtonTapped:
        return .send(.delegate(.completed))
      case .delegate:
        return .none
      }
    }
  }
}
