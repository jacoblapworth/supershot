import ComposableArchitecture

@Reducer
struct PermissionsOnboardingFeature {
  nonisolated enum Step: Equatable, Sendable {
    case alarms
    case location
  }

  @ObservableState
  struct State: Equatable {
    var errorMessage: String?
    var isRequesting = false
    var nextStep: Step?
    var step: Step

    init(step: Step = .alarms, nextStep: Step? = nil) {
      self.nextStep = nextStep
      self.step = step
    }
  }

  enum Action {
    case allowButtonTapped
    case authorizationResponse(Result<Void, any Error>)
    case delegate(Delegate)
    case notNowButtonTapped

    enum Delegate {
      case completed
    }
  }

  @Dependency(\.alarmAuthorization) var alarmAuthorization
  @Dependency(\.locationClient) var locationClient

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .allowButtonTapped:
        guard !state.isRequesting else { return .none }
        let step = state.step
        state.errorMessage = nil
        state.isRequesting = true
        return .run { send in
          await send(
            .authorizationResponse(
              await Result {
                switch step {
                case .alarms:
                  _ = try await alarmAuthorization.request()
                case .location:
                  _ = await locationClient.requestAuthorization()
                }
              }
            )
          )
        }

      case .authorizationResponse(.success):
        state.isRequesting = false
        return completeCurrentStep(state: &state)

      case .authorizationResponse(.failure):
        switch state.step {
        case .alarms:
          state.errorMessage = "Supershot couldn’t request alarm access. Try again."
        case .location:
          state.errorMessage = "Supershot couldn’t request location access. Try again."
        }
        state.isRequesting = false
        return .none

      case .delegate:
        return .none

      case .notNowButtonTapped:
        guard !state.isRequesting else { return .none }
        return completeCurrentStep(state: &state)
      }
    }
  }

  private func completeCurrentStep(state: inout State) -> Effect<Action> {
    guard let nextStep = state.nextStep else {
      return .send(.delegate(.completed))
    }
    state.errorMessage = nil
    state.nextStep = nil
    state.step = nextStep
    return .none
  }
}
