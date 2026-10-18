import AppSettings
import ComposableArchitecture
import Database
import GameAnalysis
import GameCore
import GameServices
import LocationClient
import PermissionsFeature
import PreviewSupport
import ScoringFeature
import SharedModels
import Styleguide
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import WidgetSupport

package struct SetupTeamView: View {
  @Bindable package var store: StoreOf<SetupTeamFeature>
  package var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          HStack(spacing: 16) {
            Circle().fill(store.previewTeam.color).frame(width: 56, height: 56)
              .accessibilityHidden(true)
            Text(store.previewTeam.name).font(.title2.bold())
            Spacer()
            Button {
              store.send(.changeTeamButtonTapped)
            } label: {
              Label("Change team", systemImage: "arrow.trianglehead.2.counterclockwise.rotate.90")
            }
            .buttonStyle(.bordered).disabled(store.isSaving)
            .labelStyle(.iconOnly)
          }
          PaletteColorPicker(
            color: Binding(
              get: { store.previewTeam.color }, set: { store.send(.colorChanged($0)) }),
            title: "Colour"
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
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
      }
    }
    .interactiveDismissDisabled(store.isSaving)
    .presentationDetents([.medium, .large])
    .presentationBackground(.thinMaterial)
  }

  package init(store: StoreOf<SetupTeamFeature>) {
    self.store = store
  }
}

#Preview("Selected team") {
  SetupTeamView(
    store: Store(initialState: SetupTeamFeature.State(team: .previewRavens)) {
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
