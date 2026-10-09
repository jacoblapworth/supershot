import ComposableArchitecture
import SwiftUI

struct PaywallView: View {
  @Bindable var store: StoreOf<PaywallFeature>
  
  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        ProPaywallHeader(isBusy: store.operation != nil) { store.send(.closeButtonTapped) }
        ProBenefitCarousel()
        ProPlanPicker(
          catalog: store.catalog,
          selectedProductID: store.selectedProductID,
          isBusy: store.operation != nil,
          select: { store.send(.productSelected($0)) },
          retry: { store.send(.retryButtonTapped) }
        )
        ProPurchaseSection(
          product: store.selectedProduct,
          operation: store.operation,
          purchase: { store.send(.purchaseButtonTapped) },
          restore: { store.send(.restoreButtonTapped) }
        )
      }
      .padding(24)
      .frame(maxWidth: 560)
      .frame(maxWidth: .infinity)
    }
    .background {
      LinearGradient(
        colors: [Color.accentColor.opacity(0.09), Color.accentColor.opacity(0.02), .clear],
        startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea()
    }
#if os(macOS)
    .frame(minWidth: 440, minHeight: 700)
#endif
    .interactiveDismissDisabled(store.operation != nil)
    .alert($store.scope(state: \.destination?.alert, action: \.destination.alert))
    .task { await store.send(.task).finish() }
  }
}

private struct ProPaywallHeader: View {
  let isBusy: Bool
  let close: () -> Void
  
  var body: some View {
    HStack {
      Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
      Spacer(minLength: 0)
      ViewThatFits {
        HStack(spacing: 8) { title; badge }
        VStack(spacing: 6) { title; badge }
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: 0)
      Button(action: close) {
        Image(systemName: "xmark")
          .font(.body.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: 44, height: 44)
          .background(.quaternary, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Close paywall")
      .disabled(isBusy)
    }
  }
  
  private var title: some View { Text("Supershot").font(.title.bold()) }
  private var badge: some View {
    Text("PRO")
      .font(.headline.bold())
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9))
  }
}

private struct ProBenefitCarousel: View {
  @State private var selection = 0
  @ScaledMetric(relativeTo: .body) private var textHeight = 115
  
  var body: some View {
    VStack(spacing: 16) {
      ScrollView(.horizontal) {
        HStack(spacing: 0) {
          ProBenefitSlide(
            isActivity: true,
            title: "Live Activities",
            detail: "Follow the score and timer from your Lock Screen and Dynamic Island.",
            textHeight: textHeight
          )
          .containerRelativeFrame(.horizontal)
          .id(0)
          ProBenefitSlide(
            isActivity: false,
            title: "Alarm alerts",
            detail: "Get quarter-end alerts, even when Supershot isn’t on screen.",
            textHeight: textHeight
          )
          .containerRelativeFrame(.horizontal)
          .id(1)
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollTargetBehavior(.paging)
      .scrollPosition(id: Binding($selection))
      HStack(spacing: 10) {
        ForEach(0..<2) { index in
          Button {
            withAnimation { selection = index }
          } label: {
            Circle()
              .fill(selection == index ? Color.accentColor : Color.secondary.opacity(0.2))
              .frame(width: 8, height: 8)
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(index == 0 ? "Live Activities" : "Alarm alerts")
          .accessibilityAddTraits(selection == index ? .isSelected : [])
        }
      }
    }
  }
}

private struct ProBenefitSlide: View {
  let isActivity: Bool
  let title: LocalizedStringKey
  let detail: LocalizedStringKey
  let textHeight: CGFloat
  
  var body: some View {
    VStack(spacing: 20) {
      ProBenefitIllustration(isActivity: isActivity)
        .frame(height: 170)
        .accessibilityHidden(true)
      VStack(spacing: 10) {
        Text(title).font(.title2.bold())
        Text(detail)
          .font(.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(minHeight: textHeight, alignment: .top)
    }
    .multilineTextAlignment(.center)
    .padding(.horizontal, 8)
    .accessibilityElement(children: .combine)
  }
}

private struct ProBenefitIllustration: View {
  let isActivity: Bool
  
  var body: some View {
    ZStack {
      Circle()
        .fill(Color.accentColor.opacity(0.1))
        .frame(width: 160, height: 160)
      if isActivity {
        VStack(spacing: 12) {
          Capsule().fill(.primary).frame(width: 70, height: 18)
          HStack(spacing: 20) {
            Circle().fill(Color.accentColor).frame(width: 16, height: 16)
            Text("24 : 18").font(.system(size: 28, weight: .bold, design: .rounded))
            Circle().fill(.orange).frame(width: 16, height: 16)
          }
          Label("06:42", systemImage: "timer")
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.accentColor)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(.primary.opacity(0.08)) }
        .rotationEffect(.degrees(-5))
        .shadow(color: Color.accentColor.opacity(0.12), radius: 15, y: 8)
      } else {
        Image(systemName: "clock.fill")
          .font(.system(size: 62))
          .foregroundStyle(Color.secondary.opacity(0.3))
          .offset(x: -72, y: -20)
        Image(systemName: "sportscourt.fill")
          .font(.system(size: 48))
          .foregroundStyle(Color.accentColor.opacity(0.55))
          .offset(x: 72, y: -20)
        Image(systemName: "bell.fill")
          .font(.system(size: 115))
          .foregroundStyle(Color.accentColor.gradient)
          .rotationEffect(.degrees(-15))
          .shadow(color: Color.accentColor.opacity(0.2), radius: 12, y: 8)
      }
    }
  }
}

private struct ProPlanPicker: View {
  let catalog: PaywallFeature.State.Catalog
  let selectedProductID: UUID?
  let isBusy: Bool
  let select: (UUID) -> Void
  let retry: () -> Void
  
  var body: some View {
    VStack(spacing: 14) {
      switch catalog {
      case .idle, .loading:
        ProgressView("Loading plans…").padding(24)
      case .failed:
        Text("Plans couldn’t be loaded. Check your connection and try again.")
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button("Try again", action: retry).buttonStyle(.bordered)
      case let .loaded(products):
        if products.isEmpty {
          Text("Supershot Pro is currently unavailable. Please try again later.")
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          Button("Try again", action: retry).buttonStyle(.bordered)
        } else {
          ForEach(products) { product in
            ProPlanCard(
              product: product,
              isSelected: selectedProductID == product.id,
              savings: product.savings(comparedTo: products),
              monthlyEquivalent: product.monthlyEquivalent(comparedTo: products)
            ) { select(product.id) }
          }
        }
      }
    }
    .disabled(isBusy)
  }
}

private struct ProPlanCard: View {
  let product: PaywallProduct
  let isSelected: Bool
  let savings: Int?
  let monthlyEquivalent: String?
  let select: () -> Void
  
  var body: some View {
    Button(action: select) {
      VStack(alignment: .leading, spacing: 10) {
        if let savings {
          Text("Save \(savings)%")
            .font(.subheadline.bold())
            .foregroundStyle(Color.accentColor)
        }
        HStack(alignment: .firstTextBaseline) {
          Text(product.title).font(.title3.bold())
          Spacer(minLength: 8)
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        Text(product.priceDescription)
          .font(.headline)
          .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        if product.period == nil { Text("One-time purchase").font(.subheadline).foregroundStyle(.secondary) }
        if let monthlyEquivalent {
          Text("Equivalent to \(monthlyEquivalent) / month")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        if let intro = product.introductoryOffer {
          Text(intro.description)
            .font(.subheadline.bold())
            .foregroundStyle(Color.accentColor)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
      .background(.background, in: RoundedRectangle(cornerRadius: 22))
      .overlay {
        RoundedRectangle(cornerRadius: 22)
          .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
      }
      .contentShape(RoundedRectangle(cornerRadius: 22))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct ProPurchaseSection: View {
  let product: PaywallProduct?
  let operation: PaywallFeature.State.Operation?
  let purchase: () -> Void
  let restore: () -> Void
  
  var body: some View {
    VStack(spacing: 16) {
      Button(action: purchase) {
        HStack(spacing: 10) {
          if operation == .purchasing { ProgressView().tint(.white) }
          Text(product?.purchaseButtonTitle ?? String(localized: "Unlock Supershot Pro"))
            .font(.headline)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.roundedRectangle(radius: 22))
      .controlSize(.large)
      .disabled(product == nil || operation != nil)
      if let product {
        Text(product.purchaseDetails)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      Button(action: restore) {
        HStack {
          if operation == .restoring { ProgressView() }
          Text("Restore purchases")
        }
        .frame(minHeight: 44)
      }
      .disabled(operation != nil)
      ViewThatFits {
        HStack(spacing: 20) { legalLinks }
        VStack(spacing: 12) { legalLinks }
      }
      .font(.footnote)
    }
  }
  
  private var legalLinks: some View {
    Group {
      Link("Privacy policy", destination: ProPaywallLinks.privacy)
        .frame(minHeight: 44)
      Link("Terms of use", destination: ProPaywallLinks.terms)
        .frame(minHeight: 44)
    }
  }
}

private enum ProPaywallLinks {
  static let privacy = URL(string: "https://supershot.lapworth.nz/privacy")!
  static let terms = URL(string: "https://supershot.lapworth.nz/tos")!
}

#Preview("Loaded") {
  PaywallView(
    store: Store(
      initialState: PaywallFeature.State(
        catalog: .loaded([
          .Preview.monthly,
          .Preview.yearly,
          .Preview.lifetime
        ]),
        selectedProductID: PaywallProduct.Preview.monthly.id
      )
    ) { PaywallFeature()
    })
}
