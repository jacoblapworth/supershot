import ComposableArchitecture
import SwiftUI

struct TeamSlotView: View {
  @Bindable var store: StoreOf<TeamSlotFeature>
  var teams: [Team]
  var unavailableTeamID: Team.ID?

  var body: some View {
    switch store.mode {
    case .choosing:
      TeamPickerView(
        store: store,
        teams: teams,
        unavailableTeamID: unavailableTeamID,
      )
    case .creating, .editing:
      TeamSlotEditorView(
        mode: store.mode,
        editor: $store.editor,
        existingTeamID: store.selection?.existingID,
        canFinishEditing: store.canFinishEditing,
        paletteColorTapped: { store.send(.paletteColorButtonTapped($0)) },
        cancelButtonTapped: { store.send(.cancelButtonTapped) },
        doneButtonTapped: { store.send(.doneButtonTapped) }
      )
    case .empty, .locked:
      EmptyView()
    }
  }
}


private struct TeamSlotEditorView: View {
  var mode: TeamSlotFeature.Mode
  @Binding var editor: TeamSlotFeature.TeamDraft
  var existingTeamID: Team.ID?
  var canFinishEditing: Bool
  var paletteColorTapped: (String) -> Void
  var cancelButtonTapped: () -> Void
  var doneButtonTapped: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(mode == .creating ? "Create team" : "Edit team")
        .font(.headline)

      TeamEditorFields(
        colorHex: $editor.teamColorHex,
        name: $editor.name,
        paletteColorTapped: paletteColorTapped
      )

      if existingTeamID != nil, mode == .editing {
        Label(
          "Name changes update game history. Team color changes do not change past bib colors.",
          systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      HStack {
        Button("Cancel", role: .cancel, action: cancelButtonTapped)
          .frame(maxWidth: .infinity)

        Button("Done", action: doneButtonTapped)
          .buttonStyle(.borderedProminent)
          .disabled(!canFinishEditing)
          .frame(maxWidth: .infinity)
      }
    }
    .padding()
  }
}

#Preview("Choose team") {
  TeamSlotView(
    store: Store(initialState: .previewChoosing) { TeamSlotFeature() },
    teams: .previewTeams,
    unavailableTeamID: Team.previewSwifts.id
  )
  .padding()
}

#Preview("Create team") {
  TeamSlotView(
    store: Store(initialState: .previewCreating) { TeamSlotFeature() },
    teams: .previewTeams
  )
  .padding()
}

#Preview("Edit team") {
  TeamSlotView(
    store: Store(initialState: .previewEditing) { TeamSlotFeature() },
    teams: .previewTeams
  )
  .padding()
}
