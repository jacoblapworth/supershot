import AppUI
import ComposableArchitecture
import Database
import GameCore
import PreviewSupport
import SharedModels
import SwiftUI
import UI

package struct TeamEditorView: View {
  @Bindable package var store: StoreOf<TeamEditorFeature>
  @FocusState private var focus: TeamEditorFeature.Field?

  package var body: some View {
    Form {
      Section {
        TextField("Team name", text: $store.name)
//          .textFieldStyle(.roundedBorder)
          .font(.title2)
          .fontWeight(.semibold)
          .focused($focus, equals: .name)

        #if os(macOS)
          .keyboardShortcut(.cancelAction)
        #endif
      }

      Section {
        PaletteColorPicker(
          color: $store.color
        )
      }

      if let errorMessage = store.errorMessage {
        Section {
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
      }
    }
    .disabled(store.isSaving)
    .bind($store.focus, to: $focus)
    .navigationTitle(store.isCreating ? "New team" : "Edit team")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
      .interactiveDismissDisabled(store.isSaving)
    #if os(macOS)
      .formStyle(.grouped)
      .frame(minWidth: 440, idealWidth: 480, minHeight: 320)
    #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(role: .cancel, action: { store.send(.cancelButtonTapped) })
            .disabled(store.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(role: .confirm) {
            store.send(.saveButtonTapped)
          }
          .disabled(!store.canSave)
//          Button {
//            store.send(.saveButtonTapped)
//          } label: {
//            if store.isSaving {
//              ProgressView()
//            } else {
//              Text("Save")
//            }
//          }
          #if os(macOS)
            .keyboardShortcut(.defaultAction)
          #endif
        }
      }
  }

  package init(store: StoreOf<TeamEditorFeature>) {
    self.store = store
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
