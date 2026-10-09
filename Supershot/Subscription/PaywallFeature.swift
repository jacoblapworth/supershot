import ComposableArchitecture
import Foundation

@Reducer
struct PaywallFeature {
  @ObservableState
  struct State: Equatable {
    enum Catalog: Equatable {
      case idle
      case loading
      case loaded([PaywallProduct])
      case failed
    }
    enum Operation: Equatable { case purchasing, restoring }

    var catalog: Catalog = .idle
    @Presents var destination: Destination.State?
    var operation: Operation?
    var selectedProductID: UUID?

    var products: [PaywallProduct] {
      guard case let .loaded(products) = catalog else { return [] }
      return products
    }
    var selectedProduct: PaywallProduct? {
      products.first { $0.id == selectedProductID }
    }
  }

  enum Action {
    case task
    case retryButtonTapped
    case productsResponse(Result<[PaywallProduct], Error>)
    case productSelected(UUID)
    case purchaseButtonTapped
    case purchaseResponse(Result<PaywallPurchaseOutcome, Error>)
    case restoreButtonTapped
    case restoreResponse(Result<SubscriptionEntitlement, Error>)
    case closeButtonTapped
    case customerInfoUpdated(SubscriptionEntitlement)
    case destination(PresentationAction<Destination.Action>)
    case delegate(Delegate)

    enum Delegate { case accessChanged(SubscriptionEntitlement) }
  }

  @Reducer
  enum Destination {
    case alert(AlertState<Alert>)
    enum Alert { case dismiss }
  }

  @Dependency(\.dismiss) var dismiss
  @Dependency(\.proSubscription) var proSubscription

  var body: some Reducer<State, Action> {
    Reduce<State, Action> { state, action in
      switch action {
      case .task:
        guard state.catalog == .idle else { return .none }
        return loadProducts(state: &state)

      case .retryButtonTapped:
        guard state.operation == nil, state.catalog != .loading else { return .none }
        return loadProducts(state: &state)

      case let .productsResponse(.success(products)):
        state.catalog = .loaded(products)
        state.selectedProductID = products.first(where: \.isAnnual)?.id ?? products.first?.id
        return .none

      case .productsResponse(.failure):
        state.catalog = .failed
        state.selectedProductID = nil
        return .none

      case let .productSelected(id):
        guard state.operation == nil, state.products.contains(where: { $0.id == id }) else { return .none }
        state.selectedProductID = id
        return .none

      case .purchaseButtonTapped:
        guard state.operation == nil, let product = state.selectedProduct else { return .none }
        state.operation = .purchasing
        return .run { [proSubscription] send in
          await send(.purchaseResponse(Result { try await proSubscription.purchase(product.id) }))
        }

      case let .purchaseResponse(result):
        state.operation = nil
        switch result {
        case let .success(.completed(access)):
          if access != .pro {
            state.destination = .alert(Self.alert(
              "Purchase received", "Pro access hasn’t been confirmed yet. Try Restore purchases in a moment."
            ))
          }
          return .send(.customerInfoUpdated(access))
        case .success(.cancelled): return .none
        case .success(.pending):
          state.destination = .alert(Self.alert(
            "Purchase pending", "Your purchase is awaiting approval. Supershot Pro will unlock once it is approved."
          ))
        case .failure:
          state.destination = .alert(Self.alert(
            "Unable to purchase", "Your purchase couldn’t be completed. Check your connection and try again."
          ))
        }
        return .none

      case .restoreButtonTapped:
        guard state.operation == nil else { return .none }
        state.operation = .restoring
        return .run { [proSubscription] send in
          await send(.restoreResponse(Result { try await proSubscription.restore() }))
        }

      case let .restoreResponse(.success(access)):
        state.operation = nil
        if access != .pro {
          state.destination = .alert(Self.alert(
            "Restore purchases", "No Supershot Pro purchase was found."
          ))
        }
        return .send(.customerInfoUpdated(access))

      case .restoreResponse(.failure):
        state.operation = nil
        state.destination = .alert(Self.alert(
          "Unable to restore", "Check your connection and try again. Use the Apple Account that made the purchase."
        ))
        return .none

      case .closeButtonTapped:
        guard state.operation == nil else { return .none }
        return .run { _ in await dismiss() }

      case let .customerInfoUpdated(access):
        return .send(.delegate(.accessChanged(access)))

      case .destination, .delegate:
        return .none
      }
    }
    .ifLet(\.$destination, action: \.destination) {
      Destination.body
    }
  }

  private func loadProducts(state: inout State) -> Effect<Action> {
    state.catalog = .loading
    state.selectedProductID = nil
    return .run { [proSubscription] send in
      await send(.productsResponse(Result { try await proSubscription.loadProducts() }))
    }
  }

  private static func alert(_ title: LocalizedStringResource, _ message: LocalizedStringResource) -> AlertState<Destination.Alert> {
    AlertState {
      TextState(title)
    } actions: {
      ButtonState(action: .dismiss) { TextState("OK") }
    } message: {
      TextState(message)
    }
  }
}

extension PaywallFeature.Destination.State: Equatable {}
