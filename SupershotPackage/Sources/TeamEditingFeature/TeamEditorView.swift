import AppUI
import ComposableArchitecture
import Database
import GameCore
import PhotosUI
import PreviewSupport
import SharedModels
import SwiftUI
import TeamLogoClient
import UI
import UniformTypeIdentifiers

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

      TeamLogoEditorSection(store: store)

      Section {
        if !store.logoColors.isEmpty {
          LogoColorSuggestions(colors: store.logoColors, selection: $store.color)
        }
        PaletteColorPicker(color: $store.color)
      }
      .disabled(store.isProcessingLogo)

      if let errorMessage = store.errorMessage {
        Section {
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
      }
    }
    .disabled(store.isSaving)
    .task { await store.send(.task).finish() }
    .onDisappear { store.send(.disappeared) }
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

private struct TeamLogoEditorSection: View {
  let store: StoreOf<TeamEditorFeature>
  @State private var photo: PhotosPickerItem?
  @State private var isImportingFile = false

  var body: some View {
    let hasLogo = store.logoData != nil
    Section("Logo") {
      HStack(spacing: 16) {
        AvatarView(store.name, logoData: store.logoData)
          .backgroundStyle(store.color)
          .controlSize(.extraLarge)
        if store.isProcessingLogo {
          ProgressView("Preparing logo…")
        } else {
          Text(store.logoData == nil ? "Add a team logo" : "Team logo")
            .foregroundStyle(.secondary)
        }
      }
      PhotosPicker(selection: $photo, matching: .images) {
        Label(hasLogo ? "Replace from Photos" : "Choose from Photos", systemImage: "photo")
      }
      Button("Choose from Files", systemImage: "folder") { isImportingFile = true }
      if store.logoData != nil || store.isProcessingLogo {
        Button("Remove logo", systemImage: "trash", role: .destructive) {
          photo = nil
          store.send(.removeLogoButtonTapped)
        }
      }
    }
    .onChange(of: photo) { _, item in
      guard let item else { return }
      store.send(.logoSelected(.photo(item)))
      photo = nil
    }
    .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.png, .jpeg, .heic, .heif]) { result in
      switch result {
      case let .success(url): store.send(.logoSelected(.file(url)))
      case let .failure(error):
        if (error as NSError).code != NSUserCancelledError {
          store.send(.logoImportFailed)
        }
      }
    }
  }
}

private struct LogoColorSuggestions: View {
  let colors: [String]
  @Binding var selection: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("From logo")
        .font(.subheadline.weight(.semibold))
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))], spacing: 12) {
        ForEach(colors, id: \.self) { hex in
          PaletteColorItem(color: Color(hex: hex), isSelected: selection.hex() == hex) {
            selection = Color(hex: hex)
          }
          .accessibilityLabel(Text("Logo colour \(hex)"))
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    TeamEditorView(store: Store(initialState: TeamEditorFeature.State(team: .previewRavens)) {
      TeamEditorFeature()
    })
  }
}
