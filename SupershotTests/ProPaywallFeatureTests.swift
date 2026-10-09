import ComposableArchitecture
import Foundation
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  struct ProPaywallFeatureTests {
    enum Failure: Error { case unavailable }

    nonisolated static let monthly = PaywallProduct(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
      title: "Monthly", price: 5, localizedPrice: "$5.00", currencyCode: "NZD",
      period: .init(value: 1, unit: .month), isLifetime: false,
      introductoryOffer: nil, localizedMonthlyEquivalent: "$5.00"
    )
    nonisolated static let annual = PaywallProduct(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
      title: "Yearly", price: 30, localizedPrice: "$30.00", currencyCode: "NZD",
      period: .init(value: 1, unit: .year), isLifetime: false,
      introductoryOffer: .freeTrial(.init(value: 1, unit: .week)), localizedMonthlyEquivalent: "$2.50"
    )

    @Test
    func loadPrefersAnnualAndSelectionChanges() async {
      let products = [Self.monthly, Self.annual]
      let store = TestStore(initialState: PaywallFeature.State()) { PaywallFeature() }
      withDependencies: { $0.proSubscription.loadProducts = { products } }
      await store.send(.task) { $0.catalog = .loading }
      await store.receive(\.productsResponse.success) {
        $0.catalog = .loaded(products)
        $0.selectedProductID = Self.annual.id
      }
      await store.send(.productSelected(Self.monthly.id)) { $0.selectedProductID = Self.monthly.id }
      await store.send(.task)
      await store.send(.productSelected(UUID()))
    }

    @Test
    func loadingFailureCanBeRetried() async {
      let store = TestStore(initialState: PaywallFeature.State()) { PaywallFeature() }
      withDependencies: { $0.proSubscription.loadProducts = { throw Failure.unavailable } }
      await store.send(.task) { $0.catalog = .loading }
      await store.receive(\.productsResponse.failure) { $0.catalog = .failed }
      store.dependencies.proSubscription.loadProducts = { [Self.monthly] }
      await store.send(.retryButtonTapped) { $0.catalog = .loading }
      await store.receive(\.productsResponse.success) {
        $0.catalog = .loaded([Self.monthly])
        $0.selectedProductID = Self.monthly.id
      }
    }

    @Test
    func emptyOfferingDisablesPurchaseAndCanRetry() async {
      let store = TestStore(initialState: PaywallFeature.State()) { PaywallFeature() }
      withDependencies: { $0.proSubscription.loadProducts = { [] } }
      await store.send(.task) { $0.catalog = .loading }
      await store.receive(\.productsResponse.success) { $0.catalog = .loaded([]) }
      await store.send(.purchaseButtonTapped)
      await store.send(.retryButtonTapped) { $0.catalog = .loading }
      await store.receive(\.productsResponse.success) { $0.catalog = .loaded([]) }
    }

    @Test(arguments: [PaywallFeature.State.Operation.purchasing, .restoring])
    func transactionsBlockOtherActions(operation: PaywallFeature.State.Operation) async {
      let store = TestStore(initialState: PaywallFeature.State(
        catalog: .loaded([Self.monthly, Self.annual]), operation: operation,
        selectedProductID: Self.annual.id
      )) { PaywallFeature() }
      await store.send(.purchaseButtonTapped)
      await store.send(.restoreButtonTapped)
      await store.send(.productSelected(Self.monthly.id))
      await store.send(.retryButtonTapped)
      await store.send(.closeButtonTapped)
    }

    @Test
    func purchaseUsesSelectedTokenAndDelegatesAccess() async {
      let id = Self.monthly.id
      let store = TestStore(initialState: PaywallFeature.State(
        catalog: .loaded([Self.monthly]), selectedProductID: id
      )) { PaywallFeature() }
      withDependencies: {
        $0.proSubscription.purchase = { token in
          #expect(token == id)
          return .completed(.pro)
        }
      }
      await store.send(.purchaseButtonTapped) { $0.operation = .purchasing }
      await store.receive(\.purchaseResponse.success) { $0.operation = nil }
      await store.receive(\.customerInfoUpdated)
      #expect(store.state.destination == nil)
      await store.receive {
        guard case .delegate(.accessChanged(.pro)) = $0 else { return false }
        return true
      }
    }

    @Test
    func cancellationIsSilent() async {
      let store = TestStore(initialState: PaywallFeature.State(operation: .purchasing)) { PaywallFeature() }
      await store.send(.purchaseResponse(.success(.cancelled))) { $0.operation = nil }
      #expect(store.state.destination == nil)
    }

    @Test
    func pendingAndFailureDoNotGrantAccess() async {
      let store = TestStore(initialState: PaywallFeature.State(operation: .purchasing)) { PaywallFeature() }
      store.exhaustivity = .off
      await store.send(.purchaseResponse(.success(.pending)))
      #expect(store.state.operation == nil)
      #expect(store.state.destination?.alert != nil)
      await store.send(.destination(.dismiss))
      await store.send(.purchaseResponse(.failure(Failure.unavailable)))
      #expect(store.state.destination?.alert != nil)
      await store.finish()
    }

    @Test(arguments: [SubscriptionEntitlement.pro, .free, .unknown])
    func restoreDelegatesAccessAndExplainsMissingPurchase(access: SubscriptionEntitlement) async {
      let store = TestStore(initialState: PaywallFeature.State()) { PaywallFeature() }
      withDependencies: { $0.proSubscription.restore = { access } }
      store.exhaustivity = .off
      await store.send(.restoreButtonTapped)
      #expect(store.state.operation == .restoring)
      await store.receive(\.restoreResponse.success)
      #expect(store.state.operation == nil)
      #expect((store.state.destination?.alert != nil) == (access != .pro))
      await store.receive(\.customerInfoUpdated)
      await store.receive {
        guard case let .delegate(.accessChanged(restoredAccess)) = $0 else { return false }
        return restoredAccess == access
      }
    }

    @Test
    func restoreFailureOffersRetry() async {
      let store = TestStore(initialState: PaywallFeature.State()) { PaywallFeature() }
      withDependencies: { $0.proSubscription.restore = { throw Failure.unavailable } }
      store.exhaustivity = .off
      await store.send(.restoreButtonTapped)
      await store.receive(\.restoreResponse.failure)
      #expect(store.state.operation == nil)
      #expect(store.state.destination?.alert != nil)
    }

    @Test
    func productCopyAndComparableSavings() {
      let lifetime = PaywallProduct.Preview.lifetime
      #expect(lifetime.purchaseDetails == "One-time purchase. No subscription.")
      #expect(lifetime.purchaseButtonTitle == "Unlock Supershot Pro")
      #expect(Self.monthly.priceDescription == "$5.00 / month")
      #expect(Self.annual.purchaseButtonTitle.contains("free trial"))
      #expect(Self.annual.purchaseDetails.contains("$30.00 / year"))
      #expect(Self.annual.savings(comparedTo: [Self.monthly]) == 50)
      #expect(Self.annual.monthlyEquivalent(comparedTo: [Self.monthly]) == "$2.50")
      var fractionalMonthly = Self.monthly
      fractionalMonthly.price = Decimal(string: "9.99")!
      var fractionalAnnual = Self.annual
      fractionalAnnual.price = Decimal(string: "79.99")!
      #expect(fractionalAnnual.savings(comparedTo: [fractionalMonthly]) == 33)
      var otherCurrency = Self.monthly
      otherCurrency.currencyCode = "USD"
      #expect(Self.annual.savings(comparedTo: [otherCurrency]) == nil)
      #expect(Self.annual.monthlyEquivalent(comparedTo: [otherCurrency]) == nil)
      #expect(Self.annual.savings(comparedTo: []) == nil)
      var noTrial = Self.annual
      noTrial.introductoryOffer = nil
      #expect(noTrial.purchaseButtonTitle == "Unlock Supershot Pro")
      noTrial.introductoryOffer = .discounted(price: "$1.00", period: .init(value: 1, unit: .month), payments: 3, paidUpFront: false)
      #expect(noTrial.purchaseButtonTitle == "Unlock Supershot Pro")
      #expect(noTrial.purchaseDetails.contains("$1.00 / month for 3 payments"))
    }
  }
}
