import SwiftUI

struct GamesFilterControl: View {
  let selection: GamesFilter
  var filterTapped: (GamesFilter) -> Void

  var body: some View {
    ViewThatFits(in: .horizontal) {
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
//              .padding(.horizontal, 8)
//              .padding(.vertical, 8)
              .contentShape(.capsule)
            }
            .controlSize(.small)
            .buttonStyle(.glass)
//            .glassEffect(
//              .regular.tint(selection == filter ? .accentColor.opacity(0.25) : .clear)
//                .interactive(),
//              in: .capsule
//            )
            .tint(selection == filter ? .blue : nil)
            .accessibilityLabel(Text(filter.title))
            .accessibilityAddTraits(selection == filter ? [.isSelected] : [])
            .accessibilityIdentifier("gamesFilter.\(filter.rawValue)")
          }
          Spacer()
        }
      }
      .padding(.vertical, 4)

      Menu {
        ForEach(GamesFilter.allCases) { filter in
          Button {
            filterTapped(filter)
          } label: {
            if selection == filter {
              Label(filter.title, systemImage: "checkmark")
            } else {
              Text(filter.title)
            }
          }
          .accessibilityAddTraits(selection == filter ? [.isSelected] : [])
          .accessibilityIdentifier("gamesFilter.\(filter.rawValue)")
        }
      } label: {
        ViewThatFits(in: .horizontal) {
          Label(selection.title, systemImage: "line.3.horizontal.decrease")
            .fixedSize()
          Image(systemName: "line.3.horizontal.decrease")
        }
        .font(.caption.weight(.semibold))
        .frame(minHeight: 44)
      }
      .buttonStyle(.glass)
      .accessibilityLabel("Filter games")
      .accessibilityValue(Text(selection.title))
      .accessibilityIdentifier("gamesFilter.menu")
    }
  }
}

#Preview {
  GamesFilterControl(selection: .all, filterTapped: { _ in })
    .padding()
}
