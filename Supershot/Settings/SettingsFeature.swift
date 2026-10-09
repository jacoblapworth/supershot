import ComposableArchitecture
import Foundation

@Reducer
struct SettingsFeature {
  @ObservableState
  struct State: Equatable {
    var isCustomerCenterPresented = false
#if DEBUG
    @Presents var alert: AlertState<Alert>?
    var databaseExport: DatabaseExport?

    var isDatabaseSharePresented: Bool {
      guard case .ready = databaseExport else { return false }
      return true
    }

    enum DatabaseExport: Equatable {
      case preparing
      case ready(URL)
    }
#endif
  }

  enum Action {
    case customerCenterPresentationChanged(Bool)
    case customerInfoUpdated(SubscriptionEntitlement)
    case delegate(Delegate)
    case manageSubscriptionButtonTapped
    case proPromotionTapped
#if DEBUG
    case alert(PresentationAction<Alert>)
    case databaseExportResponse(Result<URL, any Error>)
    case databaseSharePresentationChanged(Bool)
    case databaseShareCompleted(Result<Void, any Error>)
    case exportDatabaseButtonTapped
#endif

    enum Delegate {
      case proAccessChanged(SubscriptionEntitlement)
      case proPromotionTapped
    }
  }

#if DEBUG
  enum Alert { case dismissButtonTapped }
  @Dependency(DatabaseExportClient.self) var databaseExportClient
#endif

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
#if DEBUG
      case .alert:
        return .none

      case .exportDatabaseButtonTapped:
        guard state.databaseExport == nil else { return .none }
        state.databaseExport = .preparing
        return .run { send in
          await send(.databaseExportResponse(await Result {
            try await databaseExportClient.snapshot()
          }))
        }

      case let .databaseExportResponse(.success(url)):
        state.databaseExport = .ready(url)
        return .none

      case let .databaseExportResponse(.failure(error)):
        state.databaseExport = nil
        state.alert = .databaseExportFailed(error)
        return .none

      case let .databaseSharePresentationChanged(isPresented):
        guard !isPresented else { return .none }
        return dismissDatabaseShare(state: &state)

      case let .databaseShareCompleted(result):
        if case let .failure(error) = result {
          state.alert = .databaseExportFailed(error)
        }
        return dismissDatabaseShare(state: &state)
#endif
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
#if DEBUG
    .ifLet(\.$alert, action: \.alert)
#endif
  }

#if DEBUG
  private func dismissDatabaseShare(state: inout State) -> Effect<Action> {
    guard case let .ready(url) = state.databaseExport else { return .none }
    state.databaseExport = nil
    return .run { _ in
      await databaseExportClient.removeSnapshot(url)
    }
  }
#endif
}

#if DEBUG
extension AlertState where Action == SettingsFeature.Alert {
  static func databaseExportFailed(_ error: any Error) -> Self {
    Self {
      TextState("Database export failed")
    } actions: {
      ButtonState(role: .cancel, action: .dismissButtonTapped) {
        TextState("OK")
      }
    } message: {
      TextState(error.localizedDescription)
    }
  }
}
#endif
