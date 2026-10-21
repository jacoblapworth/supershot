import Dependencies
import Foundation
import RevenueCat

package nonisolated enum SubscriptionEntitlement: Equatable, Sendable {
  case free
  case pro
  case unknown

  package static let entitlementIdentifier = "Supershot Pro"

  package init(customerInfo: CustomerInfo) {
    self =
      customerInfo.entitlements[Self.entitlementIdentifier]?.isActive == true
        ? .pro
        : .free
  }

  package var isPro: Bool {
    self == .pro
  }
}

package nonisolated struct SubscriptionClient: Sendable {
  package var accessUpdates: @Sendable () -> AsyncStream<SubscriptionEntitlement>
  package var currentAccess: @Sendable () async throws -> SubscriptionEntitlement
  package var loadProducts: @Sendable () async throws -> [PaywallProduct] = { [] }
  package var purchase: @Sendable (UUID) async throws -> PaywallPurchaseOutcome = { _ in
    throw PaywallClientError.packageUnavailable
  }

  package var restore: @Sendable () async throws -> SubscriptionEntitlement = { .free }

  package init(
    accessUpdates: @escaping @Sendable () -> AsyncStream<SubscriptionEntitlement>,
    currentAccess: @escaping @Sendable () async throws -> SubscriptionEntitlement,
    loadProducts: @escaping @Sendable () async throws -> [PaywallProduct] = { [] },
    purchase: @escaping @Sendable (UUID) async throws -> PaywallPurchaseOutcome = { _ in
      throw PaywallClientError.packageUnavailable
    }, restore: @escaping @Sendable () async throws -> SubscriptionEntitlement = { .free }
  ) {
    self.accessUpdates = accessUpdates
    self.currentAccess = currentAccess
    self.loadProducts = loadProducts
    self.purchase = purchase
    self.restore = restore
  }
}

package extension DependencyValues {
  nonisolated var proSubscription: SubscriptionClient {
    get { self[ProSubscriptionClientKey.self] }
    set { self[ProSubscriptionClientKey.self] = newValue }
  }
}

private nonisolated enum ProSubscriptionClientKey: DependencyKey {
  static var liveValue: SubscriptionClient {
    .live
  }

  static var previewValue: SubscriptionClient {
    .pro
  }

  static var testValue: SubscriptionClient {
    .pro
  }
}

package nonisolated extension SubscriptionClient {
  static let free = Self(
    accessUpdates: { AsyncStream { $0.finish() } },
    currentAccess: { .free }
  )

  static var live: Self {
    let packages = PaywallPackages()
    return Self(
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
        try await SubscriptionEntitlement(customerInfo: Purchases.shared.customerInfo())
      },
      loadProducts: { try await packages.load() },
      purchase: { try await packages.purchase($0) },
      restore: {
        try await SubscriptionEntitlement(customerInfo: Purchases.shared.restorePurchases())
      }
    )
  }

  static let pro = Self(
    accessUpdates: { AsyncStream { $0.finish() } },
    currentAccess: { .pro },
    loadProducts: {
      await [
        .Preview.monthly,
        .Preview.yearly,
        .Preview.lifetime,
      ]
    },
    purchase: { _ in .completed(.pro) }
  )
}

/// Each token retains the exact package, including the offering context used to display it.
private actor PaywallPackages {
  private var packages: [UUID: Package] = [:]

  func load() async throws -> [PaywallProduct] {
    guard let offering = try await Purchases.shared.offerings().current else {
      packages = [:]
      return []
    }
    let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
      productIdentifiers: offering.availablePackages.map(\.storeProduct.productIdentifier)
    )
    var loaded: [UUID: Package] = [:]
    let products = offering.availablePackages.map { package in
      let id = UUID()
      loaded[id] = package
      let product = package.storeProduct
      var intro: PaywallProduct.IntroductoryOffer?
      if eligibility[product.productIdentifier]?.status == .eligible,
         let discount = product.introductoryDiscount
      {
        switch discount.paymentMode {
        case .freeTrial:
          intro = .freeTrial(
            Self.period(discount.subscriptionPeriod, multiplier: discount.numberOfPeriods)
          )
        case .payAsYouGo, .payUpFront:
          intro = .discounted(
            price: discount.localizedPriceString,
            period: Self.period(
              discount.subscriptionPeriod,
              multiplier: discount.paymentMode == .payUpFront ? discount.numberOfPeriods : 1
            ),
            payments: discount.numberOfPeriods,
            paidUpFront: discount.paymentMode == .payUpFront
          )
        @unknown default: break
        }
      }
      let period = product.subscriptionPeriod.map { Self.period($0) }
      let title: String = if package.packageType == .lifetime {
        String(localized: "Lifetime")
      } else if period == .init(value: 1, unit: .year) {
        String(localized: "Yearly")
      } else if period == .init(value: 1, unit: .month) {
        String(localized: "Monthly")
      } else {
        product.localizedTitle
      }
      return PaywallProduct(
        id: id, title: title, price: product.price,
        localizedPrice: product.localizedPriceString, currencyCode: product.currencyCode,
        period: period, isLifetime: package.packageType == .lifetime,
        introductoryOffer: intro, localizedMonthlyEquivalent: product.localizedPricePerMonth
      )
    }
    packages = loaded
    return products
  }

  func purchase(_ id: UUID) async throws -> PaywallPurchaseOutcome {
    guard let package = packages[id] else { throw PaywallClientError.packageUnavailable }
    do {
      let result = try await Purchases.shared.purchase(package: package)
      return result.userCancelled
        ? .cancelled : .completed(SubscriptionEntitlement(customerInfo: result.customerInfo))
    } catch {
      let error = error as NSError
      guard error.domain == ErrorCode.errorDomain else { throw error }
      switch error.code {
      case ErrorCode.purchaseCancelledError.rawValue: return .cancelled
      case ErrorCode.paymentPendingError.rawValue: return .pending
      default: throw error
      }
    }
  }

  private static func period(_ period: SubscriptionPeriod, multiplier: Int = 1)
    -> PaywallProduct.Period
  {
    let unit: PaywallProduct.Period.Unit = switch period.unit {
    case .day: .day
    case .week: .week
    case .month: .month
    case .year: .year
    @unknown default: .day
    }
    return .init(value: period.value * multiplier, unit: unit)
  }
}
