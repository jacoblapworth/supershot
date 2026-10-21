import Foundation

/// Presentational model for RevenueCat products
package nonisolated struct PaywallProduct: Equatable, Identifiable, Sendable {
  package struct Period: Equatable, Sendable {
    package enum Unit: Equatable, Sendable { case day, week, month, year }
    package var value: Int
    package var unit: Unit

    package var description: String {
      if value == 1 {
        return String(localized: "1 \(billingDescription)")
      }
      return switch unit {
      case .day: String(localized: "\(value) days")
      case .week: String(localized: "\(value) weeks")
      case .month: String(localized: "\(value) months")
      case .year: String(localized: "\(value) years")
      }
    }

    package var billingDescription: String {
      guard value == 1 else { return description }
      return switch unit {
      case .day: String(localized: "day")
      case .week: String(localized: "week")
      case .month: String(localized: "month")
      case .year: String(localized: "year")
      }
    }

    package init(value: Int, unit: Unit) {
      self.value = value
      self.unit = unit
    }
  }

  package enum IntroductoryOffer: Equatable, Sendable {
    case freeTrial(Period)
    case discounted(price: String, period: Period, payments: Int, paidUpFront: Bool)

    package var description: String {
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

  package var id: UUID
  package var title: String
  package var price: Decimal
  package var localizedPrice: String
  package var currencyCode: String?
  package var period: Period?
  package var isLifetime: Bool
  package var introductoryOffer: IntroductoryOffer?
  package var localizedMonthlyEquivalent: String?

  package var isAnnual: Bool {
    period == Period(value: 1, unit: .year)
  }

  package var priceDescription: String {
    if let period {
      return String(localized: "\(localizedPrice) / \(period.billingDescription)")
    }
    return localizedPrice
  }

  package var purchaseButtonTitle: String {
    if case let .freeTrial(period) = introductoryOffer {
      return String(localized: "Start \(period.description) free trial")
    }
    return String(localized: "Unlock Supershot Pro")
  }

  package var purchaseDetails: String {
    guard let period else { return String(localized: "One-time purchase. No subscription.") }
    let renewal = String(
      localized: "Renews at \(localizedPrice) / \(period.billingDescription). Cancel anytime."
    )
    if let introductoryOffer {
      return String(
        localized:
        "\(introductoryOffer.description). Then \(localizedPrice) / \(period.billingDescription). Auto-renews. Cancel anytime."
      )
    }
    return renewal
  }

  package func savings(comparedTo products: [Self]) -> Int? {
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

  package func monthlyEquivalent(comparedTo products: [Self]) -> String? {
    guard isAnnual, let currencyCode,
          products.contains(where: {
            $0.period == Period(value: 1, unit: .month) && $0.currencyCode == currencyCode
              && $0.price > 0
          })
    else { return nil }
    return localizedMonthlyEquivalent
  }

  package init(
    id: UUID, title: String, price: Decimal, localizedPrice: String, currencyCode: String? = nil,
    period: Period? = nil, isLifetime: Bool, introductoryOffer: IntroductoryOffer? = nil,
    localizedMonthlyEquivalent: String? = nil
  ) {
    self.id = id
    self.title = title
    self.price = price
    self.localizedPrice = localizedPrice
    self.currencyCode = currencyCode
    self.period = period
    self.isLifetime = isLifetime
    self.introductoryOffer = introductoryOffer
    self.localizedMonthlyEquivalent = localizedMonthlyEquivalent
  }
}

package nonisolated enum PaywallPurchaseOutcome: Equatable, Sendable {
  case completed(SubscriptionEntitlement)
  case cancelled
  case pending
}

package nonisolated enum PaywallClientError: Error {
  case packageUnavailable
}

package extension PaywallProduct {
  enum Preview {
    package static let lifetime = PaywallProduct(
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

    package static let yearly = PaywallProduct(
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

    package static let monthly = PaywallProduct(
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
