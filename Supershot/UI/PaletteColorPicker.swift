import SwiftUI

struct PaletteColorPicker: View {
  @Binding var color: Color
  var title: String
  var options = ColorPalette.options

  var body: some View {
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
      }

      ColorPicker("Custom color", selection: $color, supportsOpacity: false)
    }
  }
}
