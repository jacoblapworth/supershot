import ComposableArchitecture
import SwiftUI

struct ScoringView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Bindable var store: StoreOf<ScoringFeature>

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        ScoringScoreboardView(
          isDisabled: store.clockPhase == .breakTime || store.isShowingLastCentrePassBanner,
          isShowingOriginalTeamOrder: store.isShowingOriginalTeamOrder,
          teamA: store.teamA,
          teamAScore: store.teamAScore,
          teamB: store.teamB,
          teamBScore: store.teamBScore,
          goalTapped: { store.send(.goalButtonTapped($0)) }
        )

        if store.isShowingLastCentrePassBanner {
          LastCentrePassBanner(
            centrePassTeam: store.centrePassTeam,
            isTransitioningPeriod: store.isTransitioningPeriod,
            period: store.period,
            lastCentrePassNotTakenTapped: {
              store.send(.lastCentrePassNotTakenButtonTapped)
            },
            lastCentrePassTakenTapped: {
              store.send(.lastCentrePassTakenButtonTapped)
            }
          )
        } else if store.clockPhase == .quarter {
          CentrePassControl(
            centrePassTeamID: store.centrePassTeamID,
            isShowingOriginalTeamOrder: store.isShowingOriginalTeamOrder,
            teamA: store.teamA,
            teamB: store.teamB,
            centrePassTeamTapped: { store.send(.centrePassTeamButtonTapped($0)) }
          )
        }

        ScoringTimerView(
          clockPhase: store.clockPhase,
          currentDurationSeconds: store.currentDurationSeconds,
          elapsedSeconds: store.elapsedSeconds,
          isPeriodComplete: store.isPeriodComplete,
          isShowingLastCentrePassBanner: store.isShowingLastCentrePassBanner,
          isTimerRunning: store.isTimerRunning,
          pauseTimerTapped: { store.send(.pauseTimerButtonTapped) },
          resumeTimerTapped: { store.send(.resumeTimerButtonTapped) },
          startTimerTapped: { store.send(.startTimerButtonTapped) }
        )

        ScoringGameControls(
          canContinueToNextQuarter: store.canContinueToNextQuarter,
          canFinishGame: store.canFinishGame,
          canMoveToNextQuarter: store.canMoveToNextQuarter,
          clockPhase: store.clockPhase,
          isShowingLastCentrePassBanner: store.isShowingLastCentrePassBanner,
          isTransitioningPeriod: store.isTransitioningPeriod,
          period: store.period,
          continueToNextQuarterTapped: {
            store.send(.continueToNextQuarterButtonTapped)
          },
          endQuarterTapped: { store.send(.endQuarterButtonTapped) },
          finishGameTapped: { store.send(.finishGameButtonTapped) },
          skipBreakTapped: { store.send(.skipBreakButtonTapped) }
        )
      }
      .padding()
    }
    .navigationTitle(
      store.clockPhase == .breakTime
        ? "Break after quarter \(store.period)"
        : "Quarter \(store.period)"
    )
    .navigationBarBackButtonHidden()
    .toolbar {
      #if os(macOS)
      ToolbarItem(placement: .navigation) {
        gamesButton
      }
      #else
      ToolbarItem(placement: .topBarLeading) {
        gamesButton
      }
      #endif

      ToolbarItem(placement: .primaryAction) {
        Button {
          store.send(.undoButtonTapped)
        } label: {
          Image(systemName: "arrow.uturn.backward")
        }
        .disabled(!store.canUndo || store.isShowingLastCentrePassBanner)
        .accessibilityLabel("Undo last goal")
      }
    }
    .alert($store.scope(state: \.alert, action: \.alert))
    .confirmationDialog($store.scope(state: \.confirmationDialog, action: \.confirmationDialog))
    .task {
      guard scenePhase == .active else { return }
      store.send(.sceneBecameActive)
    }
    .onChange(of: scenePhase, scenePhaseChanged)
  }

  private var gamesButton: some View {
    Button {
      store.send(.closeButtonTapped)
    } label: {
      Label("Games", systemImage: "chevron.left")
    }
  }

  private func scenePhaseChanged(
    _ oldValue: ScenePhase,
    _ newValue: ScenePhase
  ) {
    store.send(newValue == .active ? .sceneBecameActive : .sceneBecameInactive)
  }
}

#Preview("Quarter") {
  NavigationStack {
    ScoringView(store: scoringPreviewStore(.previewQuarter))
  }
}

#Preview("Quarter complete") {
  NavigationStack {
    ScoringView(store: scoringPreviewStore(.previewQuarterComplete))
  }
}

#Preview("Break") {
  NavigationStack {
    ScoringView(store: scoringPreviewStore(.previewBreak))
  }
}
