import ComposableArchitecture
import SwiftUI

struct SetupBibColorsView: View {
  @Bindable var store: StoreOf<NewGameFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Bib colors", systemImage: "tshirt.fill")
        .font(.headline)

      PaletteColorPicker(
        color: $store.leftTeam.bibColor,
        title: "\(store.leftTeam.team?.name ?? "Left team") bib"
      )

      Divider()

      PaletteColorPicker(
        color: $store.rightTeam.bibColor,
        title: "\(store.rightTeam.team?.name ?? "Right team") bib"
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
