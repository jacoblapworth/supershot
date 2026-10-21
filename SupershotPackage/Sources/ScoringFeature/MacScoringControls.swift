#if os(macOS)
  import ComposableArchitecture
  import SwiftUI

  struct MacScoringControls: View {
    let store: StoreOf<ScoringFeature>

    var body: some View {
      HStack(spacing: 16) {
        ForEach([store.courtLayout.left, store.courtLayout.right]) { team in
          Button {
            store.send(.goalButtonTapped(team.id))
          } label: {
            Label("Goal for \(team.team.name)", systemImage: "plus")
              .font(.headline)
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          .tint(team.team.bibColor)
        }
      }
      .environment(\.layoutDirection, .leftToRight)
      .buttonStyle(.borderedProminent)
      .disabled(
        !store.canScoreGoal || store.controlsPresentation != .shown
          || store.alert != nil || store.isTimerOperationPending
      )
    }
  }

  /// Commands are published only by the currently visible scoring screen.
  package struct ScoringCommandContext {
    let store: StoreOf<ScoringFeature>
    let isPresentingPaywall: Bool

    package var isEnabled: Bool {
      !isPresentingPaywall && store.timeInput == nil && store.alert == nil
        && store.controlsPresentation == .shown && !store.isTimerOperationPending
        && !store.isTransitioningPeriod && !store.isSavingCourtOrientation
    }

    package var canScore: Bool {
      isEnabled && store.canScoreGoal
    }

    package var canUndo: Bool {
      isEnabled && store.canUndoGoal
    }

    package var canToggleTimer: Bool {
      isEnabled && !store.isPeriodComplete && !store.isShowingLastCentrePassBanner
    }

    package var timerTitle: String {
      store.isTimerRunning ? "Pause Timer" : "Start Timer"
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

  #Preview {
    MacScoringControls(store: scoringPreviewStore(.previewQuarter))
      .padding()
  }
#endif
