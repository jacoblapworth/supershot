import ComposableArchitecture
import SQLiteData

@Reducer
struct TeamEditorFeature {
  @ObservableState
  struct State: Equatable {
    var colorHex: String
    var errorMessage: String?
    var isSaving = false
    var name: String
    let originalColorHex: String
    let originalName: String
    let teamID: Team.ID

    init(team: Team) {
      colorHex = team.colorHex
      name = team.name
      originalColorHex = team.colorHex
      originalName = team.name
      teamID = team.id
    }

    var canSave: Bool {
      let trimmedName = Team.trimmedName(name)
      return !trimmedName.isEmpty
        && TeamColorPalette.isValid(colorHex)
        && !isSaving
        && (trimmedName != originalName || colorHex != originalColorHex)
    }
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case delegate(Delegate)
    case paletteColorButtonTapped(String)
    case saveButtonTapped
    case saveResponse(Result<Void, any Error>)

    enum Delegate: Equatable {
      case cancelled
      case saved
    }
  }

  @Dependency(\.defaultDatabase) var database

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
        guard name != state.originalName || state.colorHex != state.originalColorHex else {
          return .none
        }

        let savedTeam = Team(
          id: state.teamID,
          name: name,
          colorHex: state.colorHex
        )
        state.errorMessage = nil
        state.isSaving = true
        state.name = name
        return .run { send in
          let result = await Result {
            try await database.write { db in
              guard try Team.find(savedTeam.id).fetchOne(db) != nil else {
                throw TeamEditorPersistenceError.teamUnavailable
              }
              let teams = try Team.fetchAll(db)
              guard !teams.contains(where: {
                $0.id != savedTeam.id && $0.normalizedName == savedTeam.normalizedName
              }) else {
                throw TeamEditorPersistenceError.duplicateName
              }
              try Team.find(savedTeam.id).update {
                $0.colorHex = #bind(savedTeam.colorHex)
                $0.name = #bind(savedTeam.name)
                $0.normalizedName = #bind(savedTeam.normalizedName)
              }
              .execute(db)
            }
          }
          await send(.saveResponse(result))
        }

      case .saveResponse(.success):
        state.isSaving = false
        return .send(.delegate(.saved))

      case let .saveResponse(.failure(error)):
        state.isSaving = false
        switch error as? TeamEditorPersistenceError {
        case .duplicateName:
          state.errorMessage = "Team names must be unique."
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
  case duplicateName
  case teamUnavailable
}
