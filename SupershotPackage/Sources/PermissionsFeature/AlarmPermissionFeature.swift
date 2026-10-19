import AlarmClient
import ComposableArchitecture
import Styleguide
import SubscriptionClient

@Reducer
package struct AlarmPermissionFeature {
  @ObservableState
  package struct State: Equatable {
    package var access = SubscriptionEntitlement.unknown
    package var authorization = AlarmAuthorizationStatus.notDetermined
    package var isRequesting = false
    package var errorMessage: String?

    package init(
      access: SubscriptionEntitlement = SubscriptionEntitlement.unknown,
      authorization: AlarmAuthorizationStatus = AlarmAuthorizationStatus.notDetermined,
      isRequesting: Bool = false, errorMessage: String? = nil
    ) {
      self.access = access
      self.authorization = authorization
      self.isRequesting = isRequesting
      self.errorMessage = errorMessage
    }
  }

  package enum Action {
    case refresh(SubscriptionEntitlement)
    case enableButtonTapped
    case authorizationResponse(Result<AlarmAuthorizationStatus, any Error>)
    case delegate(Delegate)

    package enum Delegate {
      case authorized
      case proPromotionTapped
    }
  }

  @Dependency(\.alarmAuthorization) package var alarmAuthorization

  package var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .refresh(let access):
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
          await send(
            .authorizationResponse(await Result { try await alarmAuthorization.request() }))
        }

      case .authorizationResponse(.success(let status)):
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

  package init() {

  }
}
