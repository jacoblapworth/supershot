import Dependencies
import RevenueCat

nonisolated enum SubscriptionEntitlement: Equatable, Sendable {
  case free
  case pro
  case unknown

  static let entitlementIdentifier = "Supershot Pro"

  init(customerInfo: CustomerInfo) {
    print(customerInfo)
    self = customerInfo.entitlements[Self.entitlementIdentifier]?.isActive == true
      ? .pro
      : .free
  }
  
  var isPro: Bool {
    self == .pro
  }
}

nonisolated struct ProSubscriptionClient: Sendable {
  var accessUpdates: @Sendable () -> AsyncStream<SubscriptionEntitlement>
  var currentAccess: @Sendable () async throws -> SubscriptionEntitlement
}

extension DependencyValues {
  nonisolated var proSubscription: ProSubscriptionClient {
    get { self[ProSubscriptionClientKey.self] }
    set { self[ProSubscriptionClientKey.self] = newValue }
  }
}

private nonisolated enum ProSubscriptionClientKey: DependencyKey {
  static var liveValue: ProSubscriptionClient { .live }
  static var previewValue: ProSubscriptionClient { .pro }
  static var testValue: ProSubscriptionClient { .pro }
}

nonisolated extension ProSubscriptionClient {
  static let free = Self(
    accessUpdates: { AsyncStream { $0.finish() } },
    currentAccess: { .free }
  )

  static var live: Self {
    Self(
      accessUpdates: {
        AsyncStream { continuation in
          let task = Task {
            for await customerInfo in Purchases.shared.customerInfoStream {
              continuation.yield(SubscriptionEntitlement(customerInfo: customerInfo))
            }
            continuation.finish()
          }
          continuation.onTermination = { _ in task.cancel() }
        }
      },
      currentAccess: {
        SubscriptionEntitlement(customerInfo: try await Purchases.shared.customerInfo())
      }
    )
  }

  static let pro = Self(
    accessUpdates: { AsyncStream { $0.finish() } },
    currentAccess: { .pro }
  )
}
