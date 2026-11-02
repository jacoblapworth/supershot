import SwiftUI

struct GamesFilterControl: View {
  let selection: GamesFilter
  var filterTapped: (GamesFilter) -> Void

  var body: some View {
    GlassEffectContainer(spacing: 8) {
      HStack(spacing: 8) {
        ForEach(GamesFilter.allCases) { filter in
          Button {
            filterTapped(filter)
          } label: {
            HStack(spacing: 4) {
              Text(filter.title)
            }
            .font(.footnote.weight(.semibold))
            .fixedSize()
            .contentShape(.capsule)
          }
          .controlSize(.regular)
          .buttonStyle(.glass)
          .tint(selection == filter ? .blue : nil)
          .accessibilityLabel(Text(filter.title))
          .accessibilityAddTraits(selection == filter ? [.isSelected] : [])
          .accessibilityIdentifier("gamesFilter.\(filter.rawValue)")
        }
        Spacer()
      }
    }
    .padding(.vertical, 4)
  }
}

#Preview {
  GamesFilterControl(selection: .all, filterTapped: { _ in })
    .padding()
}
