import ComposableArchitecture
import Foundation
import SQLiteData

@Reducer
struct TeamSlotFeature {
  nonisolated enum Mode: Equatable, Sendable {
    case creating
    case editing
    case empty
    case choosing
    case locked

    var isInteracting: Bool {
      self == .choosing || self == .creating || self == .editing
    }
  }

  nonisolated enum Side: Equatable, Hashable, Sendable {
    case left
    case right

    var defaultColorHex: String {
      self == .left ? TeamColorPalette.blue : TeamColorPalette.red
    }

    var title: String {
      self == .left ? "Left team" : "Right team"
    }
  }

  nonisolated struct TeamDraft: Equatable, Sendable {
    var teamColorHex: String
    var name = ""

    var trimmedName: String {
      Team.trimmedName(name)
    }
  }

  nonisolated enum Selection: Equatable, Sendable {
    case existing(original: Team, draft: TeamDraft)
    case new(TeamDraft)

    var draft: TeamDraft {
      switch self {
      case let .existing(_, draft), let .new(draft):
        draft
      }
    }

    var existingID: Team.ID? {
      guard case let .existing(original, _) = self else { return nil }
      return original.id
    }

    var hasSharedChanges: Bool {
      guard case let .existing(original, draft) = self else { return false }
      return original.name != draft.trimmedName || original.colorHex != draft.teamColorHex
    }

    func updating(_ draft: TeamDraft) -> Self {
      switch self {
      case let .existing(original, _):
        .existing(original: original, draft: draft)
      case .new:
        .new(draft)
      }
    }
  }

  @ObservableState
  struct State: Equatable {
    var bibColorHex: String
    var editor: TeamDraft
    var mode = Mode.empty
    var searchText = ""
    var selection: Selection?
    let side: Side

    init(side: Side) {
      self.side = side
      self.bibColorHex = side.defaultColorHex
      self.editor = TeamDraft(teamColorHex: side.defaultColorHex)
    }

    var canFinishEditing: Bool {
      !editor.trimmedName.isEmpty && TeamColorPalette.isValid(editor.teamColorHex)
    }

    var isLocked: Bool {
      mode == .locked && selection != nil
    }

    var selectedDraft: TeamDraft? {
      selection?.draft
    }
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case bibPaletteColorButtonTapped(String)
    case cancelButtonTapped
    case cardTapped
    case changeTeamButtonTapped
    case createTeamButtonTapped
    case doneButtonTapped
    case editTeamButtonTapped
    case existingTeamSelected(Team)
    case paletteColorButtonTapped(String)
    case revertChangesButtonTapped
  }

  @Dependency(\.withRandomNumberGenerator) var withRandomNumberGenerator

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case let .bibPaletteColorButtonTapped(colorHex):
        guard state.isLocked, TeamColorPalette.isValid(colorHex) else { return .none }
        state.bibColorHex = colorHex.uppercased()
        return .none

      case .cancelButtonTapped:
        switch state.mode {
        case .choosing:
          state.mode = state.selection == nil ? .empty : .locked
        case .creating:
          state.mode = .choosing
        case .editing:
          state.mode = .locked
        case .empty, .locked:
          break
        }
        return .none

      case .cardTapped:
        guard state.mode == .empty else { return .none }
        state.mode = .choosing
        state.searchText = ""
        return .none

      case .changeTeamButtonTapped:
        guard state.mode == .locked else { return .none }
        state.mode = .choosing
        state.searchText = ""
        return .none

      case .createTeamButtonTapped:
        guard state.mode == .choosing else { return .none }
        let teamColorHex =
          withRandomNumberGenerator { generator in
            TeamColorPalette.options.randomElement(using: &generator)?.hex
          } ?? TeamColorPalette.blue
        state.editor = TeamDraft(teamColorHex: teamColorHex)
        state.mode = .creating
        return .none

      case .doneButtonTapped:
        guard state.canFinishEditing else { return .none }
        state.editor.name = state.editor.trimmedName
        switch state.mode {
        case .creating:
          state.selection = .new(state.editor)
          state.bibColorHex = state.editor.teamColorHex
          state.mode = .locked
        case .editing:
          state.selection = state.selection?.updating(state.editor)
          state.mode = .locked
        case .choosing, .empty, .locked:
          break
        }
        return .none

      case .editTeamButtonTapped:
        guard state.mode == .locked, let selection = state.selection else { return .none }
        state.editor = selection.draft
        state.mode = .editing
        return .none

      case let .existingTeamSelected(team):
        guard state.mode == .choosing else { return .none }
        let draft = TeamDraft(teamColorHex: team.colorHex, name: team.name)
        state.bibColorHex = team.colorHex
        state.selection = .existing(original: team, draft: draft)
        state.mode = .locked
        state.searchText = ""
        return .none

      case let .paletteColorButtonTapped(colorHex):
        guard state.mode == .creating || state.mode == .editing else { return .none }
        guard TeamColorPalette.isValid(colorHex) else { return .none }
        state.editor.teamColorHex = colorHex.uppercased()
        return .none

      case .revertChangesButtonTapped:
        guard case let .existing(original, _) = state.selection else { return .none }
        state.selection = .existing(
          original: original,
          draft: TeamDraft(teamColorHex: original.colorHex, name: original.name)
        )
        return .none
      }
    }
  }
}