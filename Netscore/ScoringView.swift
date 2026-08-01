import ComposableArchitecture
import SwiftUI

struct ScoringView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Bindable var store: StoreOf<ScoringFeature>

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        scoreboard
        timerPanel
        gameControls
      }
      .padding()
    }
    .navigationTitle("Quarter \(store.period)")
    .navigationBarBackButtonHidden()
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button {
          store.send(.closeButtonTapped)
        } label: {
          Label("Games", systemImage: "chevron.left")
        }
      }

      ToolbarItem(placement: .primaryAction) {
        Button {
          store.send(.undoButtonTapped)
        } label: {
          Image(systemName: "arrow.uturn.backward")
        }
        .disabled(!store.canUndo)
        .accessibilityLabel("Undo last goal")
      }
    }
    .confirmationDialog($store.scope(state: \.confirmationDialog, action: \.confirmationDialog))
    .onChange(of: scenePhase, scenePhaseChanged)
  }

  private var gameControls: some View {
    VStack(spacing: 12) {
      if store.canMoveToNextQuarter {
        Button {
          store.send(.nextQuarterButtonTapped)
        } label: {
          Label("Next quarter", systemImage: "arrow.forward.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }

      if store.canFinishGame {
        Button {
          store.send(.finishGameButtonTapped)
        } label: {
          Label("Finish game", systemImage: "flag.checkered")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private var scoreboard: some View {
    HStack(spacing: 12) {
      ScoreButton(
        name: store.teamA.name,
        score: store.teamAScore
      ) {
        store.send(.goalButtonTapped(store.teamA.id))
      }

      ScoreButton(
        name: store.teamB.name,
        score: store.teamBScore
      ) {
        store.send(.goalButtonTapped(store.teamB.id))
      }
    }
  }

  private var timerPanel: some View {
    VStack(spacing: 16) {
      Text(formattedTime(store.timeRemainingSeconds))
        .font(.system(size: 56, weight: .bold, design: .rounded))
        .monospacedDigit()
        .frame(maxWidth: .infinity)

      ProgressView(
        value: Double(store.elapsedSeconds),
        total: Double(store.periodDurationSeconds)
      )

      HStack {
        if store.isTimerRunning {
          Button {
            store.send(.pauseTimerButtonTapped)
          } label: {
            Label("Pause", systemImage: "pause.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
        } else if store.elapsedSeconds == 0 {
          Button {
            store.send(.startTimerButtonTapped)
          } label: {
            Label("Start", systemImage: "play.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
        } else {
          Button {
            store.send(.resumeTimerButtonTapped)
          } label: {
            Label("Resume", systemImage: "play.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .disabled(store.isPeriodComplete)
        }
      }
    }
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
  }

  private func formattedTime(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let seconds = seconds % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
  }

  private func scenePhaseChanged(
    _ oldValue: ScenePhase,
    _ newValue: ScenePhase
  ) {
    guard newValue != .active else { return }
    store.send(.sceneBecameInactive)
  }
}

private struct ScoreButton: View {
  var name: String
  var score: Int
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 10) {
        Text(name)
          .font(.headline)
          .lineLimit(2)
          .multilineTextAlignment(.center)
          .frame(minHeight: 44)

        Text("\(score)")
          .font(.system(size: 64, weight: .bold, design: .rounded))
          .monospacedDigit()

        Label("Goal", systemImage: "plus.circle.fill")
          .font(.subheadline.weight(.semibold))
      }
      .frame(maxWidth: .infinity, minHeight: 180)
    }
    .buttonStyle(.bordered)
  }
}

#Preview {
  ScoringView(
    store: Store(
      initialState: ScoringFeature.State(
        gameID: UUID(),
        startedAt: Date(),
        teamA: ScoringFeature.Team(id: UUID(), name: "Ravens"),
        teamB: ScoringFeature.Team(id: UUID(), name: "Swifts")
      )
    ) {
      ScoringFeature()
    }
  )
}
