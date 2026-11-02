import ComposableArchitecture
import Database
import GameCore
import PermissionsFeature
import ScoringFeature
import SQLiteData

/// The read-only entry point for an existing, unstarted game.
@Reducer
package struct PlannedGameFeature {
  @ObservableState
  package struct State: Equatable {
    package let gameID: Game.ID
    package var snapshot: GameSnapshot?
    @Presents package var editor: NewGameFeature.State?
    package var alarms = AlarmPermissionFeature.State()
    package var isLoading = false
    package var hasPreparedScoring = false
    package var errorMessage: String?
    package var failedIntent = LoadIntent.refresh

    package init(snapshot: GameSnapshot) {
      gameID = snapshot.game.id
      self.snapshot = snapshot
    }
  }

  package enum LoadIntent: Equatable, Sendable {
    case refresh, edit, score
  }

  package enum Action {
    case refresh
    case editButtonTapped
    case startGameButtonTapped
    case retryButtonTapped
    case snapshotResponse(LoadIntent, Result<GameSnapshot, any Error>)
    case editor(PresentationAction<NewGameFeature.Action>)
    case editorDismissalSaved(Result<GameSnapshot, any Error>, NewGameFeature.State)
    case alarms(AlarmPermissionFeature.Action)
    case delegate(Delegate)

    package enum Delegate {
      case scoringPrepared(ScoringFeature.State)
      case lifecycleChanged(Game.ID)
      case proPromotionTapped
    }
  }

  @Dependency(\.defaultDatabase) var database

  package var body: some Reducer<State, Action> {
    Scope(state: \.alarms, action: \.alarms) { AlarmPermissionFeature() }
    Reduce { state, action in
      switch action {
      case .refresh:
        return load(.refresh, state: &state)

      case .editButtonTapped:
        return load(.edit, state: &state)

      case .startGameButtonTapped:
        return load(.score, state: &state)

      case .retryButtonTapped:
        return load(state.failedIntent, state: &state)

      case let .snapshotResponse(intent, .success(snapshot)):
        state.isLoading = false
        state.errorMessage = nil
        state.snapshot = snapshot
        guard snapshot.game.isPlanned else {
          return .send(.delegate(.lifecycleChanged(state.gameID)))
        }
        switch intent {
        case .refresh:
          return .none
        case .edit:
          state.editor = NewGameFeature.State(snapshot: snapshot)
          return .none
        case .score:
          state.hasPreparedScoring = true
          return .send(.delegate(.scoringPrepared(ScoringFeature.State(snapshot: snapshot))))
        }

      case let .snapshotResponse(intent, .failure):
        state.isLoading = false
        state.snapshot = nil
        state.failedIntent = intent
        state.errorMessage = "This game could not be opened. It may have been deleted. Try again."
        return .none

      case .editor(.presented(.delegate(.gameSaved))):
        state.editor = nil
        return .merge(
          load(.refresh, state: &state),
          .send(.alarms(.refresh(state.alarms.access)))
        )

      case let .editor(.presented(.delegate(.scoringPrepared(scoring)))):
        state.editor = nil
        state.hasPreparedScoring = true
        return .send(.delegate(.scoringPrepared(scoring)))

      case .editor(.presented(.delegate(.proPromotionTapped))),
           .alarms(.delegate(.proPromotionTapped)):
        return .send(.delegate(.proPromotionTapped))

      case .editor(.dismiss):
        guard let editor = state.editor, !editor.hasEnteredScoring,
              editor.describeGame.source.isEmpty,
              let draft = editor.draft, draft != editor.lastSavedDraft
        else {
          // PresentationReducer clears the editor after this reducer runs.
          state.editor = nil
          return .merge(
            load(.refresh, state: &state),
            .send(.alarms(.refresh(state.alarms.access)))
          )
        }
        state.isLoading = true
        return .run { send in
          let result = await Result {
            try await database.write { try draft.save($0, requiresExistingGame: true) }
          }
          await send(.editorDismissalSaved(result, editor))
        }

      case let .editorDismissalSaved(.success(snapshot), _):
        state.isLoading = false
        state.snapshot = snapshot
        state.errorMessage = nil
        return .send(.alarms(.refresh(state.alarms.access)))

      case var .editorDismissalSaved(.failure, editor):
        state.isLoading = false
        editor.isSaving = false
        editor.inFlightDraft = nil
        editor.pendingSaveIntent = nil
        editor.closesAfterSave = true
        editor.failedSaveIntent = .close
        editor.errorMessage = "Could not save the game. Your changes are still here. Try again."
        state.editor = editor
        return .none

      case .editor, .alarms, .delegate:
        return .none
      }
    }
    .ifLet(\.$editor, action: \.editor) { NewGameFeature() }
  }

  private func load(_ intent: LoadIntent, state: inout State) -> Effect<Action> {
    guard !state.isLoading, state.editor == nil, !state.hasPreparedScoring else { return .none }
    state.isLoading = true
    state.errorMessage = nil
    let gameID = state.gameID
    return .run { send in
      let result = await Result {
        try await database.read { try GameSnapshot.fetch($0, gameID: gameID) }
      }
      guard !Task.isCancelled else { return }
      await send(.snapshotResponse(intent, result))
    }
  }

  package init() {}
}
