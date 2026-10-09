import ComposableArchitecture

@Reducer
struct AlarmPermissionFeature {
  @ObservableState
  struct State: Equatable {
    var access = SubscriptionEntitlement.unknown
    var authorization = AlarmAuthorizationStatus.notDetermined
    var isRequesting = false
    var errorMessage: String?
  }

  enum Action {
    case refresh(SubscriptionEntitlement)
    case enableButtonTapped
    case authorizationResponse(Result<AlarmAuthorizationStatus, any Error>)
    case delegate(Delegate)

    enum Delegate {
      case authorized
      case proPromotionTapped
    }
  }

  @Dependency(\.alarmAuthorization) var alarmAuthorization

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case let .refresh(access):
        state.access = access
        guard !state.isRequesting else { return .none }
        let previous = state.authorization
        state.authorization = alarmAuthorization.status()
        if state.authorization != previous { state.errorMessage = nil }
        if access == .pro, previous != .authorized, state.authorization == .authorized {
          return .send(.delegate(.authorized))
        }
        return .none

      case .enableButtonTapped:
        guard !state.isRequesting, state.access != .unknown else { return .none }
        guard state.access == .pro else {
          return .send(.delegate(.proPromotionTapped))
        }
        guard state.authorization == .notDetermined else { return .none }
        state.isRequesting = true
        state.errorMessage = nil
        return .run { send in
          await send(.authorizationResponse(await Result { try await alarmAuthorization.request() }))
        }

      case let .authorizationResponse(.success(status)):
        state.isRequesting = false
        state.authorization = status
        if status == .authorized { return .send(.delegate(.authorized)) }
        return .none

      case .authorizationResponse(.failure):
        state.isRequesting = false
        state.errorMessage = "Supershot couldn’t request alarm access. Try again."
        return .none

      case .delegate:
        return .none
      }
    }
  }
}
