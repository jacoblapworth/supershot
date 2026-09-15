import ComposableArchitecture

@Reducer
struct SettingsFeature {
  @ObservableState
  struct State: Equatable {
    var isCustomerCenterPresented = false
  }

  enum Action {
    case customerCenterPresentationChanged(Bool)
    case customerInfoUpdated(SubscriptionEntitlement)
    case delegate(Delegate)
    case manageSubscriptionButtonTapped
    case proPromotionTapped

    enum Delegate {
      case proAccessChanged(SubscriptionEntitlement)
      case proPromotionTapped
    }
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case let .customerCenterPresentationChanged(isPresented):
        state.isCustomerCenterPresented = isPresented
        return .none

      case let .customerInfoUpdated(access):
        return .send(.delegate(.proAccessChanged(access)))

      case .delegate:
        return .none

      case .manageSubscriptionButtonTapped:
        state.isCustomerCenterPresented = true
        return .none

      case .proPromotionTapped:
        return .send(.delegate(.proPromotionTapped))
      }
    }
  }
}
