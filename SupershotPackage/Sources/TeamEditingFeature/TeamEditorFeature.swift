import AppUI
import ComposableArchitecture
import Database
import Foundation
import GameCore
import PreviewSupport
import SharedModels
import SQLiteData
import SwiftUI
import TeamLogoClient
import UI

@Reducer
package struct TeamEditorFeature {
  @ObservableState
  package struct State: Equatable {
    package enum Mode: Equatable {
      case creating
      case editing(Team.ID)
    }

    package var focus: Field? = .name
    package var color: Color
    package var errorMessage: String?
    package var isSaving = false
    package var isProcessingLogo = false
    package var logoData: Data?
    package var logoColors: [String] = []
    package var logoRequestID: UUID?
    package var name: String
    package var mode: Mode
    package let originalColor: Color
    package let originalName: String
    package let originalLogoData: Data?

    package init(team: Team) {
      focus = .name
      color = team.color
      name = team.name
      mode = .editing(team.id)
      originalColor = team.color
      originalName = team.name
      logoData = team.logoData
      originalLogoData = team.logoData
    }

    package init() {
      focus = .name
      color = ColorPalette.blue
      name = ""
      mode = .creating
      originalColor = ColorPalette.blue
      originalName = ""
      originalLogoData = nil
    }

    package var isCreating: Bool {
      mode == .creating
    }

    package var canSave: Bool {
      let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
      return !trimmedName.isEmpty
        && !isSaving
        && !isProcessingLogo
        && (isCreating || trimmedName != originalName || color != originalColor || logoData != originalLogoData)
    }
  }

  package enum Action: BindableAction {
    case binding(BindingAction<State>)
    case cancelButtonTapped
    case delegate(Delegate)
    case disappeared
    case logoImportFailed
    case logoSelected(TeamLogoSource)
    case logoResponse(UUID, Result<PreparedTeamLogo, any Error>)
    case removeLogoButtonTapped
    case saveButtonTapped
    case saveResponse(Result<Team, any Error>)
    case task

    package enum Delegate: Equatable {
      case cancelled
      case saved(Team)
    }
  }

  package nonisolated enum Field: Hashable, Sendable {
    case name
  }

  @Dependency(\.defaultDatabase) package var database
  @Dependency(\.uuid) package var uuid
  @Dependency(\.teamLogoClient) package var teamLogoClient

  private nonisolated enum CancelID: Hashable, Sendable { case logo }

  package var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        state.errorMessage = nil
        return .none

      case .cancelButtonTapped:
        guard !state.isSaving else { return .none }
        state.logoRequestID = nil
        state.isProcessingLogo = false
        return .merge(.cancel(id: CancelID.logo), .send(.delegate(.cancelled)))

      case .disappeared:
        state.logoRequestID = nil
        state.isProcessingLogo = false
        return .cancel(id: CancelID.logo)

      case .task:
        guard let data = state.logoData, state.logoRequestID == nil, state.logoColors.isEmpty else { return .none }
        let requestID = uuid()
        state.logoRequestID = requestID
        return .run { send in
          let result = await Result { try await teamLogoClient.colors(data) }
          await send(.logoResponse(requestID, result.map { PreparedTeamLogo(data: data, colors: $0) }))
        }
        .cancellable(id: CancelID.logo, cancelInFlight: true)

      case let .logoSelected(source):
        guard !state.isSaving else { return .none }
        let requestID = uuid()
        state.logoRequestID = requestID
        state.isProcessingLogo = true
        state.errorMessage = nil
        state.focus = nil
        return .run { send in
          let result = await Result { try await teamLogoClient.prepare(source) }
          await send(.logoResponse(requestID, result))
        }
        .cancellable(id: CancelID.logo, cancelInFlight: true)

      case let .logoResponse(requestID, result):
        guard state.logoRequestID == requestID else { return .none }
        let isImport = state.isProcessingLogo
        state.logoRequestID = nil
        state.isProcessingLogo = false
        switch result {
        case let .success(logo):
          state.logoData = logo.data
          state.logoColors = logo.colors
          if isImport, let color = logo.colors.first {
            state.color = Color(hex: color)
          }
        case .failure:
          if isImport {
            state.errorMessage = "Couldn’t open this logo. Choose a PNG, JPEG, or HEIC image and try again."
          }
        }
        return .none

      case .logoImportFailed:
        state.errorMessage = "Couldn’t open this logo. Try choosing the image again."
        return .none

      case .removeLogoButtonTapped:
        guard !state.isSaving else { return .none }
        state.logoData = nil
        state.logoColors = []
        state.logoRequestID = nil
        state.isProcessingLogo = false
        state.errorMessage = nil
        return .cancel(id: CancelID.logo)

      case .delegate:
        return .none

      case .saveButtonTapped:
        guard !state.isSaving, !state.isProcessingLogo else { return .none }
        let name = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
          state.errorMessage = "Enter a team name."
          return .none
        }
        guard state.isCreating || name != state.originalName || state.color != state.originalColor
          || state.logoData != state.originalLogoData
        else {
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
          colorHex: state.color.hex(),
          logoData: state.logoData
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
                  $0.logoData = #bind(savedTeam.logoData)
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

  package init() {}
}

private enum TeamEditorPersistenceError: Error {
  case teamUnavailable
}
