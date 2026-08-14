import ComposableArchitecture
import SQLiteData

@Reducer
struct TeamEditorFeature {
  @ObservableState
  struct State: Equatable {
    enum Mode: Equatable {
      case creating
      case editing(Team.ID)
    }

    var focus: Field? = .name
    var colorHex: String
    var errorMessage: String?
    var isSaving = false
    var name: String
    var mode: Mode
    let originalColorHex: String
    let originalName: String

    init(team: Team) {
      focus = .name
      colorHex = team.colorHex
      name = team.name
      mode = .editing(team.id)
      originalColorHex = team.colorHex
      originalName = team.name
    }

    init() {
      focus = .name
      colorHex = TeamColorPalette.blue
      name = ""
      mode = .creating
      originalColorHex = TeamColorPalette.blue
      originalName = ""
    }

    var isCreating: Bool {
      mode == .creating
    }

    var canSave: Bool {
      let trimmedName = Team.trimmedName(name)
      return !trimmedName.isEmpty
        && TeamColorPalette.isValid(colorHex)
        && !isSaving
        && (isCreating || trimmedName != originalName || colorHex != originalColorHex)
    }
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case delegate(Delegate)
    case paletteColorButtonTapped(String)
    case saveButtonTapped
    case saveResponse(Result<Team, any Error>)

    enum Delegate: Equatable {
      case cancelled
      case saved(Team)
    }
  }
  
  nonisolated enum Field: Hashable, Sendable {
    case name
  }

  @Dependency(\.defaultDatabase) var database
  @Dependency(\.uuid) var uuid

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        state.errorMessage = nil
        return .none

      case .cancelButtonTapped:
        guard !state.isSaving else { return .none }
        return .send(.delegate(.cancelled))

      case .delegate:
        return .none

      case let .paletteColorButtonTapped(colorHex):
        guard TeamColorPalette.isValid(colorHex) else { return .none }
        state.colorHex = colorHex.uppercased()
        state.errorMessage = nil
        return .none

      case .saveButtonTapped:
        guard !state.isSaving else { return .none }
        let name = Team.trimmedName(state.name)
        guard !name.isEmpty else {
          state.errorMessage = "Enter a team name."
          return .none
        }
        guard TeamColorPalette.isValid(state.colorHex) else {
          state.errorMessage = "Choose a valid team color."
          return .none
        }
        guard state.isCreating || name != state.originalName || state.colorHex != state.originalColorHex else {
          return .none
        }

        let savedTeam = Team(
          id: {
            if case let .editing(teamID) = state.mode {
              return teamID
            }
            return uuid()
          }(),
          name: name,
          colorHex: state.colorHex
        )
        let isCreating = state.isCreating
        state.errorMessage = nil
        state.isSaving = true
        state.name = name
        return .run { send in
          let result = await Result {
            try await database.write { db in
              if isCreating {
                try Team.insert { savedTeam }.execute(db)
              } else {
                guard try Team.find(savedTeam.id).fetchOne(db) != nil else {
                  throw TeamEditorPersistenceError.teamUnavailable
                }
                try Team.find(savedTeam.id).update {
                  $0.colorHex = #bind(savedTeam.colorHex)
                  $0.name = #bind(savedTeam.name)
                }
                .execute(db)
              }
            }
            return savedTeam
          }
          await send(.saveResponse(result))
        }

      case let .saveResponse(.success(savedTeam)):
        state.isSaving = false
        return .send(.delegate(.saved(savedTeam)))

      case let .saveResponse(.failure(error)):
        state.isSaving = false
        switch error as? TeamEditorPersistenceError {
        case .teamUnavailable:
          state.errorMessage = "This team is no longer available."
        case nil:
          state.errorMessage = "Couldn’t save team. Try again."
        }
        return .none
      }
    }
  }
}

private enum TeamEditorPersistenceError: Error {
  case teamUnavailable
}
