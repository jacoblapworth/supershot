import Dependencies
import RevenueCat

nonisolated enum ProAccess: Equatable, Sendable {
  case free
  case pro
  case unknown

  static let entitlementIdentifier = "pro"

  init(customerInfo: CustomerInfo) {
    self = customerInfo.entitlements[Self.entitlementIdentifier]?.isActive == true
      ? .pro
      : .free
  }
}

nonisolated struct ProSubscriptionClient: Sendable {
  var accessUpdates: @Sendable () -> AsyncStream<ProAccess>
  var currentAccess: @Sendable () async throws -> ProAccess
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
              continuation.yield(ProAccess(customerInfo: customerInfo))
            }
            continuation.finish()
          }
          continuation.onTermination = { _ in task.cancel() }
        }
      },
      currentAccess: {
        ProAccess(customerInfo: try await Purchases.shared.customerInfo())
      }
    )
  }

  static let pro = Self(
    accessUpdates: { AsyncStream { $0.finish() } },
    currentAccess: { .pro }
  )
}
