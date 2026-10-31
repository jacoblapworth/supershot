import AlarmClient
import ComposableArchitecture
import FeatureFlagsClient
import SubscriptionClient
import UI

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
    case statusResponse(AlarmAuthorizationStatus)
    case authorizationResponse(Result<AlarmAuthorizationStatus, any Error>)
    case delegate(Delegate)

    package enum Delegate {
      case authorized
      case proPromotionTapped
    }
  }

  @Dependency(\.alarmAuthorization) package var alarmAuthorization
  @Dependency(\.featureFlags) package var featureFlags

  package var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case let .refresh(access):
        state.access = access
        guard !state.isRequesting else { return .none }
        return .run { send in
          await send(.statusResponse(alarmAuthorization.status()))
        }
        .cancellable(id: "authorizationStatus", cancelInFlight: true)

      case let .statusResponse(status):
        guard !state.isRequesting else { return .none }
        let previous = state.authorization
        state.authorization = status
        if state.authorization != previous {
          state.errorMessage = nil
        }
        if featureFlags.isEnabled(.timerAlerts, state.access), previous != .authorized,
           state.authorization == .authorized
        {
          return .send(.delegate(.authorized))
        }
        return .none

      case .enableButtonTapped:
        guard !state.isRequesting, state.access != .unknown else { return .none }
        guard featureFlags.isEnabled(.timerAlerts, state.access) else {
          return .send(.delegate(.proPromotionTapped))
        }
        guard state.authorization == .notDetermined else { return .none }
        state.isRequesting = true
        state.errorMessage = nil
        return .merge(
          .cancel(id: "authorizationStatus"),
          .run { send in
            await send(.authorizationResponse(Result { try await alarmAuthorization.request() }))
          }
        )

      case let .authorizationResponse(.success(status)):
        state.isRequesting = false
        state.authorization = status
        if status == .authorized, featureFlags.isEnabled(.timerAlerts, state.access) {
          return .send(.delegate(.authorized))
        }
        return .none

      case .authorizationResponse(.failure):
        state.isRequesting = false
        #if os(macOS)
          state.errorMessage = "Supershot couldn’t request notification access. Try again."
        #else
          state.errorMessage = "Supershot couldn’t request alarm access. Try again."
        #endif
        return .none

      case .delegate:
        return .none
      }
    }
  }

  package init() {}
}
