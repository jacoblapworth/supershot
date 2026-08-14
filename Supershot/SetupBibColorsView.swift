import ComposableArchitecture
import SwiftUI

struct SetupBibColorsView: View {
  @Bindable var store: StoreOf<NewGameFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Bib colors", systemImage: "tshirt.fill")
        .font(.headline)

      TeamColorPicker(
      colorHex: $store.leftTeam.bibColorHex,
      title: "\(store.leftTeam.team?.name ?? "Left team") bib",
      paletteColorTapped: { store.leftTeam.bibColorHex = $0 }
      )

      Divider()

      TeamColorPicker(
      colorHex: $store.rightTeam.bibColorHex,
      title: "\(store.rightTeam.team?.name ?? "Right team") bib",
      paletteColorTapped: { store.rightTeam.bibColorHex = $0 }
      )
    }
    .setupCardStyle()
  }
}

#Preview {
  SetupBibColorsView(
    store: setupPreviewStore(.previewReady)
  )
  .padding()
}
