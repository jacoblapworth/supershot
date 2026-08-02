import ComposableArchitecture
import SwiftUI

struct SetupBibColorsView: View {
  @Bindable var leftStore: StoreOf<TeamSlotFeature>
  @Bindable var rightStore: StoreOf<TeamSlotFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Bib colors", systemImage: "tshirt.fill")
        .font(.headline)

      TeamColorPicker(
        colorHex: $leftStore.bibColorHex,
        title: "\(leftStore.selectedDraft?.trimmedName ?? "Left team") bib",
        paletteColorTapped: { leftStore.send(.bibPaletteColorButtonTapped($0)) }
      )

      Divider()

      TeamColorPicker(
        colorHex: $rightStore.bibColorHex,
        title: "\(rightStore.selectedDraft?.trimmedName ?? "Right team") bib",
        paletteColorTapped: { rightStore.send(.bibPaletteColorButtonTapped($0)) }
      )
    }
    .setupCardStyle()
  }
}

#Preview {
  SetupBibColorsView(
    leftStore: setupPreviewStore(.previewReady).scope(
      state: \.leftTeam,
      action: \.leftTeam
    ),
    rightStore: setupPreviewStore(.previewReady).scope(
      state: \.rightTeam,
      action: \.rightTeam
    )
  )
  .padding()
}
