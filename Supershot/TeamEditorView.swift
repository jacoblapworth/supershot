import ComposableArchitecture
import SwiftUI

struct TeamEditorView: View {
  @Bindable var store: StoreOf<TeamEditorFeature>

  var body: some View {
    Form {
      Section {
        TeamEditorFields(
          colorHex: $store.colorHex,
          name: $store.name,
          paletteColorTapped: { store.send(.paletteColorButtonTapped($0)) }
        )
        .disabled(store.isSaving)
      }

      Section {
        Label(
          "Changes update this saved team in previous and future games.",
          systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }

      if let errorMessage = store.errorMessage {
        Section {
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
      }
    }
    .navigationTitle("Edit team")
    .navigationBarTitleDisplayMode(.inline)
    .interactiveDismissDisabled(store.isSaving)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          store.send(.cancelButtonTapped)
        }
        .disabled(store.isSaving)
      }
      ToolbarItem(placement: .confirmationAction) {
        Button {
          store.send(.saveButtonTapped)
        } label: {
          if store.isSaving {
            ProgressView()
          } else {
            Text("Save")
          }
        }
        .disabled(!store.canSave)
      }
    }
  }
}

#Preview {
  NavigationStack {
    TeamEditorView(
      store: Store(
        initialState: TeamEditorFeature.State(team: .previewRavens)
      ) {
        TeamEditorFeature()
      }
    )
  }
}
