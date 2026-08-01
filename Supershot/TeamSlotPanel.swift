import ComposableArchitecture
import SwiftUI

struct TeamSlotPanel: View {
  @Bindable var store: StoreOf<TeamSlotFeature>
  var teams: [Team]
  var unavailableTeamID: Team.ID?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      switch store.mode {
      case .choosing:
        chooseTeamContent
      case .creating, .editing:
        editTeamContent
      case .empty, .locked:
        EmptyView()
      }
    }
    .setupCardStyle()
  }

  private var chooseTeamContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Choose \(store.side.title.lowercased())")
        .font(.headline)

      if !teams.isEmpty {
        TextField("Search teams", text: $store.searchText)
          .textFieldStyle(.roundedBorder)

        LazyVStack(spacing: 8) {
          ForEach(filteredTeams) { team in
            Button {
              store.send(.existingTeamSelected(team))
            } label: {
              HStack(spacing: 12) {
                Circle()
                  .fill(Color(teamHex: team.colorHex))
                  .frame(width: 18, height: 18)
                  .accessibilityHidden(true)
                Text(team.name)
                  .foregroundStyle(.primary)
                Spacer()
                if team.id == unavailableTeamID {
                  Text("Already selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                  Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                }
              }
              .padding(12)
              .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(team.id == unavailableTeamID)
            .accessibilityHint(
              team.id == unavailableTeamID ? "Already selected on the other side" : ""
            )
          }
        }
      } else {
        ContentUnavailableView(
          "No saved teams",
          systemImage: "person.2",
          description: Text("Create your first reusable team.")
        )
      }

      Button {
        store.send(.createTeamButtonTapped)
      } label: {
        Label("Create new team", systemImage: "plus.circle.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)

      Button("Cancel", role: .cancel) {
        store.send(.cancelButtonTapped)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var editTeamContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(store.mode == .creating ? "Create team" : "Edit team")
        .font(.headline)

      TextField("Team name", text: $store.editor.name)
        .textFieldStyle(.roundedBorder)

      VStack(alignment: .leading, spacing: 10) {
        Text("Team color")
          .font(.subheadline.weight(.semibold))

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))], spacing: 12) {
          ForEach(TeamColorPalette.options) { option in
            Button {
              store.send(.paletteColorButtonTapped(option.hex))
            } label: {
              Circle()
                .fill(Color(teamHex: option.hex))
                .frame(width: 34, height: 34)
                .overlay {
                  if store.editor.colorHex == option.hex {
                    Image(systemName: "checkmark")
                      .font(.caption.bold())
                      .foregroundStyle(.white)
                  }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(option.name)
            .accessibilityAddTraits(store.editor.colorHex == option.hex ? .isSelected : [])
          }
        }

        TeamCustomColorPicker(colorHex: $store.editor.colorHex)
      }

      if store.selection?.existingID != nil, store.mode == .editing {
        Label(
          "Changes update this saved team in previous and future games.",
          systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      HStack {
        Button("Cancel", role: .cancel) {
          store.send(.cancelButtonTapped)
        }
        .frame(maxWidth: .infinity)

        Button("Done") {
          store.send(.doneButtonTapped)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!store.canFinishEditing)
        .frame(maxWidth: .infinity)
      }
    }
  }

  private var filteredTeams: [Team] {
    let query = Team.normalizeName(store.searchText)
    guard !query.isEmpty else { return teams }
    return teams.filter { $0.normalizedName.contains(query) }
  }
}

private struct TeamCustomColorPicker: View {
  @Binding var colorHex: String
  @Environment(\.self) private var environment
  @State private var color: Color

  init(colorHex: Binding<String>) {
    self._colorHex = colorHex
    self._color = State(initialValue: Color(teamHex: colorHex.wrappedValue))
  }

  var body: some View {
    ColorPicker("Custom color", selection: $color, supportsOpacity: false)
      .onChange(of: color) { _, newValue in
        let resolved = newValue.resolve(in: environment)
        colorHex = String(
          format: "#%02X%02X%02X",
          Int((Double(resolved.red) * 255).rounded()),
          Int((Double(resolved.green) * 255).rounded()),
          Int((Double(resolved.blue) * 255).rounded())
        )
      }
  }
}

#Preview("Choose team") {
  TeamSlotPanel(
    store: Store(initialState: .previewChoosing) { TeamSlotFeature() },
    teams: .previewTeams,
    unavailableTeamID: Team.previewSwifts.id
  )
  .padding()
}

#Preview("Create team") {
  TeamSlotPanel(
    store: Store(initialState: .previewCreating) { TeamSlotFeature() },
    teams: .previewTeams
  )
  .padding()
}

#Preview("Edit team") {
  TeamSlotPanel(
    store: Store(initialState: .previewEditing) { TeamSlotFeature() },
    teams: .previewTeams
  )
  .padding()
}
