#if os(macOS)
  import ComposableArchitecture
  import GameCore
  import SwiftUI

  /// Commands are published only by the currently visible scoring screen.
  package struct ScoringCommandContext {
    let store: StoreOf<ScoringFeature>
    let isPresentingPaywall: Bool

    package var isEnabled: Bool {
      !isPresentingPaywall && store.canOperate && !store.isSavingCourtOrientation
    }

    package var canScore: Bool {
      isEnabled && store.canScoreGoal
    }

    package var canUndo: Bool {
      isEnabled && store.canUndoGoal
    }

    package var canToggleTimer: Bool {
      isEnabled && (store.canPause || store.canStartOrResume)
    }

    package var timerTitle: String {
      if store.canPause {
        return "Pause Timer"
      }
      if case let .primary(control) = store.scoringToolbarState.content {
        return control.title
      }
      return store.phaseStatus == .paused ? "Resume Timer" : "Start Break"
    }

    package var leftTitle: String {
      "Goal for \(store.courtLayout.left.team.name) (Left)"
    }

    package var rightTitle: String {
      "Goal for \(store.courtLayout.right.team.name) (Right)"
    }

    package func toggleTimer() {
      guard canToggleTimer else { return }
      store.send(store.isTimerRunning ? .pauseTimerButtonTapped : .startTimerButtonTapped)
    }

    package func goal(left: Bool) {
      guard canScore else { return }
      store.send(.goalButtonTapped(left ? store.courtLayout.left.id : store.courtLayout.right.id))
    }

    package func undo() {
      guard canUndo else { return }
      store.send(.undoButtonTapped)
    }
  }

  private struct ScoringCommandsKey: FocusedValueKey {
    typealias Value = ScoringCommandContext
  }

  package extension FocusedValues {
    var scoringCommands: ScoringCommandContext? {
      get { self[ScoringCommandsKey.self] }
      set { self[ScoringCommandsKey.self] = newValue }
    }
  }

#endif
