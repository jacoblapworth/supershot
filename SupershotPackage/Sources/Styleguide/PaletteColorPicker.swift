import GameCore
import SharedModels
import SwiftUI
import WidgetSupport

package struct PaletteColorPicker: View {
  @Binding package var color: Color
  package var title: String
  package var options = ColorPalette.options

  package var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.subheadline.weight(.semibold))

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))], spacing: 12) {
        ForEach(options) { option in
          Button {
            color = option.color
          } label: {
            Circle()
              .fill(option.color)
              .frame(width: 34, height: 34)
              .overlay {
                if color == option.color {
                  Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                }
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(option.name)
          .accessibilityAddTraits(color == option.color ? .isSelected : [])
        }
        ColorPicker(
          "Custom color",
          selection: $color,
          supportsOpacity: false
        )
        .labelsHidden()
      }
    }
  }

  package init(
    color: Binding<Color>, title: String, options: [ColorPalette.Option] = ColorPalette.options
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
