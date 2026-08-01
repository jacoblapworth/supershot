import ComposableArchitecture
import SwiftUI

struct SetupView: View {
  @Bindable var store: StoreOf<SetupFeature>

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        matchupCard

        if store.leftTeam.mode.isInteracting {
          TeamSlotPanel(
            store: store.scope(state: \.leftTeam, action: \.leftTeam),
            teams: store.availableTeams,
            unavailableTeamID: store.rightTeam.selection?.existingID
          )
        } else if store.rightTeam.mode.isInteracting {
          TeamSlotPanel(
            store: store.scope(state: \.rightTeam, action: \.rightTeam),
            teams: store.availableTeams,
            unavailableTeamID: store.leftTeam.selection?.existingID
          )
        }

        if store.leftTeam.isLocked, store.rightTeam.isLocked {
          centrePassCard
        }

        timingCard
      }
      .padding()
    }
    .navigationTitle("New game")
    .safeAreaInset(edge: .bottom) {
      startGameBar
    }
    .confirmationDialog(
      $store.scope(state: \.confirmationDialog, action: \.confirmationDialog)
    )
    .task {
      store.send(.task)
    }
  }

  private var centrePassCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("First centre pass", systemImage: "arrow.left.arrow.right")
        .font(.headline)

      Picker("First centre pass", selection: $store.firstCentrePass) {
        Text(store.leftTeam.selectedDraft?.trimmedName ?? "Left")
          .tag(SetupFeature.TeamSide?.some(.teamA))
        Text(store.rightTeam.selectedDraft?.trimmedName ?? "Right")
          .tag(SetupFeature.TeamSide?.some(.teamB))
      }
      .pickerStyle(.segmented)
    }
    .cardStyle()
  }

  private var matchupCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Matchup", systemImage: "person.2.fill")
        .font(.headline)

      HStack(spacing: 10) {
        TeamCard(
          isDisabled: store.rightTeam.mode.isInteracting || store.isSaving,
          store: store.scope(state: \.leftTeam, action: \.leftTeam)
        )

        Button {
          store.send(.swapTeamsButtonTapped)
        } label: {
          Image(systemName: "arrow.left.arrow.right")
            .font(.headline)
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.bordered)
        .disabled(!store.canSwapTeams)
        .accessibilityLabel("Swap left and right teams")

        TeamCard(
          isDisabled: store.leftTeam.mode.isInteracting || store.isSaving,
          store: store.scope(state: \.rightTeam, action: \.rightTeam)
        )
      }

      if store.isLoadingTeams {
        HStack(spacing: 8) {
          ProgressView()
          Text("Loading saved teams…")
            .foregroundStyle(.secondary)
        }
        .font(.subheadline)
      }
    }
    .cardStyle()
  }

  private var startGameBar: some View {
    VStack(spacing: 10) {
      Text(store.configurationSummary)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      if let message = store.teamNameErrorMessage ?? store.errorMessage {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Button {
        store.send(.startGameButtonTapped)
      } label: {
        if store.isSaving {
          ProgressView()
            .frame(maxWidth: .infinity)
        } else {
          Label("Start game", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(!store.canStartGame)
    }
    .padding()
    .background(.bar)
  }

  private var timingCard: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("Timing", systemImage: "timer")
        .font(.headline)

      DurationEditor(
        duration: $store.periodDuration,
        label: "Quarter length",
        presets: [6, 10, 12, 15, 20].map { $0 * 60 },
        presetTapped: { store.send(.periodPresetButtonTapped($0)) }
      )

      Divider()

      if store.customizesBreaks {
        DurationEditor(
          duration: $store.firstBreakDuration,
          label: "After quarter 1",
          presets: [0, 1, 2, 4, 5].map { $0 * 60 },
          presetTapped: { store.send(.firstBreakPresetButtonTapped($0)) }
        )
        DurationEditor(
          duration: $store.halfTimeDuration,
          label: "Half time",
          presets: [0, 1, 2, 4, 5, 8, 10, 12].map { $0 * 60 },
          presetTapped: { store.send(.halfTimePresetButtonTapped($0)) }
        )
        DurationEditor(
          duration: $store.secondBreakDuration,
          label: "After quarter 3",
          presets: [0, 1, 2, 4, 5].map { $0 * 60 },
          presetTapped: { store.send(.secondBreakPresetButtonTapped($0)) }
        )

        Button("Use first break for all") {
          store.send(.useFirstBreakForAllButtonTapped)
        }
        .buttonStyle(.bordered)
      } else {
        DurationEditor(
          duration: $store.firstBreakDuration,
          label: "All breaks",
          presets: [0, 1, 2, 4, 5].map { $0 * 60 },
          presetTapped: { store.send(.allBreakPresetButtonTapped($0)) }
        )

        Button("Customize each break") {
          store.send(.customizeBreaksButtonTapped)
        }
        .buttonStyle(.bordered)
      }
    }
    .cardStyle()
  }
}

private struct TeamCard: View {
  var isDisabled: Bool
  @Bindable var store: StoreOf<TeamSlotFeature>

  var body: some View {
    VStack(spacing: 10) {
      if let draft = store.selectedDraft {
        Circle()
          .fill(Color(teamHex: draft.colorHex))
          .frame(width: 30, height: 30)
          .overlay {
            Circle().stroke(.white.opacity(0.8), lineWidth: 2)
          }
          .accessibilityHidden(true)

        Text(draft.trimmedName)
          .font(.headline)
          .lineLimit(2)
          .multilineTextAlignment(.center)

        if store.mode == .locked {
          HStack(spacing: 8) {
            Button("Change") {
              store.send(.changeTeamButtonTapped)
            }
            Button("Edit") {
              store.send(.editTeamButtonTapped)
            }
          }
          .font(.caption)
          .buttonStyle(.bordered)

          if store.selection?.hasSharedChanges == true {
            VStack(spacing: 6) {
              Label("Updates history", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.caption2)
                .foregroundStyle(.orange)
              Button("Revert edits") {
                store.send(.revertChangesButtonTapped)
              }
              .font(.caption)
            }
          }
        } else {
          Text("Choosing…")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else {
        Button {
          store.send(.cardTapped)
        } label: {
          VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
              .font(.title)
            Text(store.side.title)
              .font(.headline)
            Text("Tap to choose")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 150)
    .padding(10)
    .background(
      Color(teamHex: store.selectedDraft?.colorHex ?? store.side.defaultColorHex).opacity(0.09),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          store.mode.isInteracting
            ? Color(teamHex: store.selectedDraft?.colorHex ?? store.side.defaultColorHex)
            : Color.secondary.opacity(0.25),
          lineWidth: store.mode.isInteracting ? 2 : 1
        )
    }
    .disabled(isDisabled)
  }
}

private struct TeamSlotPanel: View {
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
    .cardStyle()
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
            .accessibilityHint(team.id == unavailableTeamID ? "Already selected on the other side" : "")
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

private struct DurationEditor: View {
  @Binding var duration: SetupFeature.DurationDraft
  var label: String
  var presets: [Int]
  var presetTapped: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(label)
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text(duration.formatted)
          .font(.subheadline.monospacedDigit().weight(.semibold))
          .foregroundStyle(duration.totalSeconds == nil ? Color.red : Color.secondary)
      }

      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(presets, id: \.self) { seconds in
            Button {
              presetTapped(seconds)
            } label: {
              if duration.totalSeconds == seconds {
                Label(formatted(seconds), systemImage: "checkmark")
              } else {
                Text(formatted(seconds))
              }
            }
            .buttonStyle(.bordered)
          }
        }
      }
      .scrollIndicators(.hidden)

      HStack(spacing: 8) {
        TextField("Minutes", text: $duration.minutesText)
          .textFieldStyle(.roundedBorder)
        Text("min")
          .foregroundStyle(.secondary)
        TextField("Seconds", text: $duration.secondsText)
          .textFieldStyle(.roundedBorder)
        Text("sec")
          .foregroundStyle(.secondary)
      }
      .font(.subheadline)
    }
  }

  private func formatted(_ seconds: Int) -> String {
    "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
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

private extension View {
  func cardStyle() -> some View {
    self
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}

#Preview {
  NavigationStack {
    SetupView(
      store: Store(initialState: SetupFeature.State()) {
        SetupFeature()
      }
    )
  }
}
