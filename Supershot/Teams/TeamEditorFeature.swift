import SwiftUI
import ComposableArchitecture
import SQLiteData
import Foundation

@Reducer
struct TeamEditorFeature {
  @ObservableState
  struct State: Equatable {
    enum Mode: Equatable {
      case creating
      case editing(Team.ID)
    }

    var focus: Field? = .name
    var color: Color
    var errorMessage: String?
    var isSaving = false
    var name: String
    var mode: Mode
    let originalColor: Color
    let originalName: String

    init(team: Team) {
      focus = .name
      color = team.color
      name = team.name
      mode = .editing(team.id)
      originalColor = team.color
      originalName = team.name
    }

    init() {
      focus = .name
      color = ColorPalette.blue
      name = ""
      mode = .creating
      originalColor = ColorPalette.blue
      originalName = ""
    }

    var isCreating: Bool {
      mode == .creating
    }

    var canSave: Bool {
      let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
      return !trimmedName.isEmpty
        && !isSaving
        && (isCreating || trimmedName != originalName || color != originalColor)
    }
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case delegate(Delegate)
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

      case .saveButtonTapped:
        guard !state.isSaving else { return .none }
        let name = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
          state.errorMessage = "Enter a team name."
          return .none
        }
        guard state.isCreating || name != state.originalName || state.color != state.originalColor else {
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
          colorHex: state.color.hex()
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
