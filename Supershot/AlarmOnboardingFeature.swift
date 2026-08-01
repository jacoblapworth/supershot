import ComposableArchitecture

@Reducer
struct AlarmOnboardingFeature {
  @ObservableState
  struct State: Equatable {
    var errorMessage: String?
    var isRequesting = false
  }

  enum Action {
    case allowAlarmsButtonTapped
    case authorizationResponse(Result<AlarmAuthorizationStatus, any Error>)
    case delegate(Delegate)
    case notNowButtonTapped

    enum Delegate {
      case completed
    }
  }

  @Dependency(\.alarmAuthorization) var alarmAuthorization

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .allowAlarmsButtonTapped:
        guard !state.isRequesting else { return .none }
        state.errorMessage = nil
        state.isRequesting = true
        return .run { send in
          await send(
            .authorizationResponse(
              await Result {
                try await alarmAuthorization.request()
              }
            )
          )
        }

      case .authorizationResponse(.success):
        state.isRequesting = false
        return .send(.delegate(.completed))

      case .authorizationResponse(.failure):
        state.errorMessage = "Supershot couldn’t request alarm access. Try again."
        state.isRequesting = false
        return .none

      case .delegate:
        return .none

      case .notNowButtonTapped:
        guard !state.isRequesting else { return .none }
        return .send(.delegate(.completed))
      }
    }
  }
}
