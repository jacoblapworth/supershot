import ComposableArchitecture
import Database
import Foundation
import GameCore
import SQLiteData

@Reducer
package struct TeamFavoriteFeature {
  @ObservableState
  package struct State: Equatable {
    @Presents package var alert: AlertState<Action.Alert>?
    package var savingTeamIDs: Set<Team.ID> = []
    package init() {}
  }

  package enum Action {
    case alert(PresentationAction<Alert>)
    case favoriteButtonTapped(Team.ID, isFavorite: Bool)
    case saveResponse(Team.ID, Result<Void, any Error>)

    package enum Alert: Equatable {
      case dismiss
    }
  }

  @Dependency(\.defaultDatabase) var database

  package var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .alert:
        return .none
      case let .favoriteButtonTapped(teamID, isFavorite):
        guard state.savingTeamIDs.insert(teamID).inserted else { return .none }
        return .run { send in
          let result = await Result {
            try await database.write { db in
              try TeamFavorite.setFavorite(!isFavorite, teamID: teamID, in: db)
            }
          }
          await send(.saveResponse(teamID, result))
        }
      case let .saveResponse(teamID, result):
        state.savingTeamIDs.remove(teamID)
        if case .failure = result {
          state.alert = AlertState {
            TextState("Could not update favorite")
          } actions: {
            ButtonState(role: .cancel, action: .dismiss) { TextState("OK") }
          } message: {
            TextState("Your favorite preference was not changed. Try again. The team may have been deleted.")
          }
        }
        return .none
      }
    }
    .ifLet(\.$alert, action: \.alert)
  }

  package init() {}
}
