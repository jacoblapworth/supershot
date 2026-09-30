import ComposableArchitecture
import SwiftUI

struct SetupTeamView: View {
  @Bindable var store: StoreOf<SetupTeamFeature>
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          HStack(spacing: 16) {
            Circle().fill(store.previewTeam.color).frame(width: 56, height: 56)
              .accessibilityHidden(true)
            Text(store.previewTeam.name).font(.title2.bold())
          }
          Button("Change team") { store.send(.changeTeamButtonTapped) }
            .buttonStyle(.bordered).disabled(store.isSaving)
          PaletteColorPicker(
            color: Binding(get: { store.previewTeam.color }, set: { store.send(.colorChanged($0)) }),
            title: "Bib colour"
          )
          if store.isSaving { ProgressView("Saving colour…") }
          if let errorMessage = store.errorMessage {
            Text(errorMessage).foregroundStyle(.red)
            Button("Retry") { store.send(.retryButtonTapped) }
          }
        }.padding()
      }
      .navigationTitle("Team")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { store.send(.doneButtonTapped) }.disabled(store.isSaving)
        }
      }
      .sheet(item: $store.scope(state: \.picker, action: \.picker)) { picker in
        NavigationStack {
          TeamPickerView(store: picker).navigationTitle("Select team")
        }.presentationDetents([.medium, .large])
      }
    }
    .interactiveDismissDisabled(store.isSaving)
    .presentationDetents([.medium, .large])
  }
}

#Preview("Selected team") {
  SetupTeamView(store: Store(initialState: SetupTeamFeature.State(team: .previewRavens)) {
    SetupTeamFeature()
  })
}

#Preview("Save error") {
  let state = {
    var state = SetupTeamFeature.State(team: .previewRavens)
    state.errorMessage = "Couldn’t save bib colour. Try again."
    state.failedColorHex = ColorPalette.red.hex()
    return state
  }()
  SetupTeamView(store: Store(initialState: state) { SetupTeamFeature() })
}
