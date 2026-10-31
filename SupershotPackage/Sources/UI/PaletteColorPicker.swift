import SwiftUI

package struct PaletteColorPicker: View {
  @Binding package var color: Color
  package var title: String?
  package var options = ColorPalette.options

  package var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let title {
        Text(title)
          .font(.subheadline.weight(.semibold))
      }

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))], spacing: 12) {
        ForEach(options) { option in
          PaletteColorItem(
            color: option.color,
            isSelected: color == option.color
          ) {
            color = option.color
          }
        }
        ColorPicker(
          "Custom color",
          selection: $color,
          supportsOpacity: false
        )
        .controlSize(.large)
        .labelsHidden()
      }
    }
  }

  package init(
    color: Binding<Color>,
    title: String? = nil,
    options: [ColorPalette.Option] = ColorPalette.options
  ) {
    _color = color
    self.title = title
    self.options = options
  }
}

#Preview {
  @Previewable @State var color: Color = .blue
  PaletteColorPicker(color: $color, title: "Colour")
}

package struct PaletteColorItem: View {
  package var color: Color
  package var isSelected: Bool = false
  package var onSelect: () -> Void

  package var body: some View {
    Button {
      withAnimation {
        onSelect()
      }
    } label: {
      Circle()
        .fill(color)
        .frame(width: 40, height: 40)
        .overlay {
          if isSelected {
            Image(systemName: "checkmark")
              .transition(.symbolEffect(.drawOn))
              .font(.caption.bold())
              .foregroundStyle(.white)
            Circle()
              .inset(by: -2)
              .stroke(.tertiary, lineWidth: 2)
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(color.description)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
