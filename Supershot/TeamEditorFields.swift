import SwiftUI

struct TeamColorPicker: View {
  @Binding var colorHex: String
  var title: String
  var paletteColorTapped: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.subheadline.weight(.semibold))

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))], spacing: 12) {
        ForEach(TeamColorPalette.options) { option in
          Button {
            paletteColorTapped(option.hex)
          } label: {
            Circle()
              .fill(Color(teamHex: option.hex))
              .frame(width: 34, height: 34)
              .overlay {
                if colorHex == option.hex {
                  Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                }
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(option.name)
          .accessibilityAddTraits(colorHex == option.hex ? .isSelected : [])
        }
      }

      TeamCustomColorPicker(colorHex: $colorHex)
    }
  }
}

private struct TeamCustomColorPicker: View {
  @Binding var colorHex: String
  @Environment(\.self) private var environment
  @State private var color: Color

  init(colorHex: Binding<String>) {
    self._colorHex = colorHex
    self._color = State(initialValue: Color(teamHex: colorHex.wrappedValue))
  }

  var body: some View {
    ColorPicker("Custom color", selection: $color, supportsOpacity: false)
      .onChange(of: color) { _, newValue in
        let resolved = newValue.resolve(in: environment)
        colorHex = String(
          format: "#%02X%02X%02X",
          Int((Double(resolved.red) * 255).rounded()),
          Int((Double(resolved.green) * 255).rounded()),
          Int((Double(resolved.blue) * 255).rounded())
        )
      }
  }
}
