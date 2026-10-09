import Foundation

/// Presentational model for RevenueCat products
nonisolated struct PaywallProduct: Equatable, Identifiable, Sendable {
  struct Period: Equatable, Sendable {
    enum Unit: Equatable, Sendable { case day, week, month, year }
    var value: Int
    var unit: Unit

    var description: String {
      if value == 1 { return String(localized: "1 \(billingDescription)") }
      return switch unit {
      case .day: String(localized: "\(value) days")
      case .week: String(localized: "\(value) weeks")
      case .month: String(localized: "\(value) months")
      case .year: String(localized: "\(value) years")
      }
    }

    var billingDescription: String {
      guard value == 1 else { return description }
      return switch unit {
      case .day: String(localized: "day")
      case .week: String(localized: "week")
      case .month: String(localized: "month")
      case .year: String(localized: "year")
      }
    }
  }

  enum IntroductoryOffer: Equatable, Sendable {
    case freeTrial(Period)
    case discounted(price: String, period: Period, payments: Int, paidUpFront: Bool)

    var description: String {
      switch self {
      case let .freeTrial(period):
        String(localized: "\(period.description) free")
      case let .discounted(price, period, payments, paidUpFront):
        if paidUpFront {
          String(localized: "\(price) for the first \(period.description)")
        } else {
          String(localized: "\(price) / \(period.billingDescription) for \(payments) payments")
        }
      }
    }
  }

  var id: UUID
  var title: String
  var price: Decimal
  var localizedPrice: String
  var currencyCode: String?
  var period: Period?
  var isLifetime: Bool
  var introductoryOffer: IntroductoryOffer?
  var localizedMonthlyEquivalent: String?

  var isAnnual: Bool { period == Period(value: 1, unit: .year) }

  var priceDescription: String {
    if let period { return String(localized: "\(localizedPrice) / \(period.billingDescription)") }
    return localizedPrice
  }

  var purchaseButtonTitle: String {
    if case let .freeTrial(period) = introductoryOffer {
      return String(localized: "Start \(period.description) free trial")
    }
    return String(localized: "Unlock Supershot Pro")
  }

  var purchaseDetails: String {
    guard let period else { return String(localized: "One-time purchase. No subscription.") }
    let renewal = String(localized: "Renews at \(localizedPrice) / \(period.billingDescription). Cancel anytime.")
    if let introductoryOffer {
      return String(localized: "\(introductoryOffer.description). Then \(localizedPrice) / \(period.billingDescription). Auto-renews. Cancel anytime.")
    }
    return renewal
  }

  func savings(comparedTo products: [Self]) -> Int? {
    guard isAnnual, let currencyCode,
      let monthly = products.first(where: {
        $0.period == Period(value: 1, unit: .month) && $0.currencyCode == currencyCode
      }), monthly.price > 0, price > 0, price < monthly.price * 12
    else { return nil }
    let percentage = NSDecimalNumber(decimal: (1 - price / (monthly.price * 12)) * 100).doubleValue
    guard percentage.isFinite else { return nil }
    let rounded = Int(percentage.rounded(.down))
    return rounded > 0 ? rounded : nil
  }

  func monthlyEquivalent(comparedTo products: [Self]) -> String? {
    guard isAnnual, let currencyCode, products.contains(where: {
      $0.period == Period(value: 1, unit: .month) && $0.currencyCode == currencyCode && $0.price > 0
    }) else { return nil }
    return localizedMonthlyEquivalent
  }
}

nonisolated enum PaywallPurchaseOutcome: Equatable, Sendable {
  case completed(SubscriptionEntitlement)
  case cancelled
  case pending
}

nonisolated enum PaywallClientError: Error {
  case packageUnavailable
}

extension PaywallProduct {
  enum Preview {
    static let lifetime = PaywallProduct(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      title: "Lifetime",
      price: 49.99,
      localizedPrice: "$49.99",
      currencyCode: "NZD",
      period: nil,
      isLifetime: true,
      introductoryOffer: nil,
      localizedMonthlyEquivalent: nil
    )
    
    static let yearly = PaywallProduct(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
      title: "Yearly",
      price: 19.99,
      localizedPrice: "$19.99",
      currencyCode: "NZD",
      period: .init(value: 1, unit: .year),
      isLifetime: false,
      introductoryOffer: nil,
      localizedMonthlyEquivalent: "$1.67"
    )
    
    static let monthly = PaywallProduct(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
      title: "Monthly",
      price: 2.99,
      localizedPrice: "$2.99",
      currencyCode: "NZD",
      period: .init(value: 1, unit: .month),
      isLifetime: false,
      introductoryOffer: nil,
      localizedMonthlyEquivalent: nil
    )
  }
}
