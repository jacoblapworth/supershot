import SwiftUI

struct ProPromotionCard: View {
  var exploreProTapped: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Supershot Pro", systemImage: "crown.fill")
        .font(.title3.bold())
        .foregroundStyle(Color.accentColor)

      Text(
        "Get Live Activities and alarm alerts on iPhone and iPad, "
          + "so every quarter stays on time."
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      Button("Explore Pro", action: exploreProTapped)
        .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(
      Color.accentColor.opacity(0.1),
      in: RoundedRectangle(cornerRadius: 16)
    )
    .accessibilityElement(children: .contain)
  }
}

#Preview {
  ProPromotionCard(exploreProTapped: {})
    .padding()
}
