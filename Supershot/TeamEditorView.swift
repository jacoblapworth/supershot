import ComposableArchitecture
import SwiftUI

struct TeamEditorView: View {
  @Bindable var store: StoreOf<TeamEditorFeature>
  @FocusState private var focus: TeamEditorFeature.Field?

  var body: some View {
    Form {
      Section {
        TextField("Team name", text: $store.name)
          .textFieldStyle(.roundedBorder)
          .focused($focus, equals: .name)
          .disabled(store.isSaving)
        TeamColorPicker(
          colorHex: $store.colorHex,
          title: "Team color",
          paletteColorTapped: { store.send(.paletteColorButtonTapped($0)) }
        )
          .disabled(store.isSaving)
      }

      Section {
        Label(
          "Name changes update game history. Team color changes do not change past bib colors.",
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
    .bind($store.focus, to: $focus)
    .navigationTitle(store.isCreating ? "New team" : "Edit team")
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    .interactiveDismissDisabled(store.isSaving)
#endif
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

