import ComposableArchitecture

@Reducer
struct ProPaywallFeature {
  @ObservableState
  struct State: Equatable {}

  enum Action {
    case customerInfoUpdated(SubscriptionEntitlement)
    case delegate(Delegate)

    enum Delegate {
      case accessChanged(SubscriptionEntitlement)
    }
  }

  var body: some Reducer<State, Action> {
    Reduce { _, action in
      switch action {
      case let .customerInfoUpdated(access):
        return .send(.delegate(.accessChanged(access)))

      case .delegate:
        return .none
      }
    }
  }
}
