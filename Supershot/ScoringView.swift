import ComposableArchitecture
import SwiftUI

struct ScoringView: View {
  @Environment(\.scenePhase) private var scenePhase
  @Bindable var store: StoreOf<ScoringFeature>

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        scoreboard
        if store.isShowingLastCentrePassBanner {
          lastCentrePassBanner
        } else if store.clockPhase == .quarter {
          centrePassControl
        }
        timerPanel
        gameControls
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
    .confirmationDialog($store.scope(state: \.confirmationDialog, action: \.confirmationDialog))
    .onChange(of: scenePhase, scenePhaseChanged)
  }

  private var gamesButton: some View {
    Button {
      store.send(.closeButtonTapped)
    } label: {
      Label("Games", systemImage: "chevron.left")
    }
  }

  private var gameControls: some View {
    VStack(spacing: 12) {
      if store.canContinueToNextQuarter {
        Button {
          store.send(.continueToNextQuarterButtonTapped)
        } label: {
          Label("Continue to quarter \(store.period + 1)", systemImage: "arrow.forward.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      } else if store.clockPhase == .breakTime {
        Button {
          store.send(.skipBreakButtonTapped)
        } label: {
          Label("Skip break", systemImage: "forward.end.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(store.isShowingLastCentrePassBanner || store.isTransitioningPeriod)
      } else if store.canMoveToNextQuarter {
        Button {
          store.send(.endQuarterButtonTapped)
        } label: {
          Label("End quarter", systemImage: "stop.circle.fill")
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

  private var lastCentrePassBanner: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Quarter \(store.period) complete", systemImage: "flag.checkered")
        .font(.headline)

      HStack(spacing: 8) {
        Circle()
          .fill(Color(teamHex: store.centrePassTeam.colorHex))
          .frame(width: 12, height: 12)
          .accessibilityHidden(true)
        Text("Did **\(store.centrePassTeam.name)** take the last centre pass?")
      }

      HStack(spacing: 10) {
        Button("No, not taken") {
          store.send(.lastCentrePassNotTakenButtonTapped)
        }
        .buttonStyle(.bordered)

        Button("Yes, pass taken") {
          store.send(.lastCentrePassTakenButtonTapped)
        }
        .buttonStyle(.borderedProminent)
      }
      .disabled(store.isTransitioningPeriod)

      if store.isTransitioningPeriod {
        ProgressView("Saving quarter…")
          .font(.caption)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.accentColor, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }

  private var centrePassControl: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Centre pass", systemImage: "arrow.left.arrow.right")
        .font(.headline)

      HStack(spacing: 12) {
        if store.isShowingOriginalTeamOrder {
          centrePassButton(team: store.teamA)
          centrePassButton(team: store.teamB)
        } else {
          centrePassButton(team: store.teamB)
          centrePassButton(team: store.teamA)
        }
      }

      Text("Tap a team to correct the next centre pass.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
  }

  private var scoreboard: some View {
    HStack(spacing: 12) {
      if store.isShowingOriginalTeamOrder {
        scoreButton(team: store.teamA, score: store.teamAScore)
        scoreButton(team: store.teamB, score: store.teamBScore)
      } else {
        scoreButton(team: store.teamB, score: store.teamBScore)
        scoreButton(team: store.teamA, score: store.teamAScore)
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
        total: Double(max(store.currentDurationSeconds, 1))
      )

      if !store.isShowingLastCentrePassBanner || store.clockPhase == .breakTime {
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
    }
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
  }

  private func centrePassButton(team: ScoringFeature.Team) -> some View {
    CentrePassButton(
      colorHex: team.colorHex,
      isSelected: store.centrePassTeamID == team.id,
      name: team.name
    ) {
      store.send(.centrePassTeamButtonTapped(team.id))
    }
  }

  private func scoreButton(
    team: ScoringFeature.Team,
    score: Int
  ) -> some View {
    ScoreButton(
      colorHex: team.colorHex,
      isDisabled: store.clockPhase == .breakTime || store.isShowingLastCentrePassBanner,
      name: team.name,
      score: score
    ) {
      store.send(.goalButtonTapped(team.id))
    }
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
  var colorHex: String
  var isDisabled: Bool
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
      .background(
        Color(teamHex: colorHex).opacity(0.12),
        in: RoundedRectangle(cornerRadius: 12)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color(teamHex: colorHex), lineWidth: 2)
      }
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.65 : 1)
  }
}

private struct CentrePassButton: View {
  var colorHex: String
  var isSelected: Bool
  var name: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        Text(name)
          .lineLimit(2)
          .multilineTextAlignment(.center)
      }
      .font(.subheadline.weight(.semibold))
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.horizontal, 8)
      .foregroundStyle(Color.primary)
      .background(
        isSelected ? Color(teamHex: colorHex).opacity(0.2) : Color.clear,
        in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(
            isSelected ? Color(teamHex: colorHex) : Color.secondary.opacity(0.4),
            lineWidth: isSelected ? 2 : 1
          )
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(name) centre pass")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

#Preview {
  let teamAID = UUID()
  let teamBID = UUID()
  ScoringView(
    store: Store(
      initialState: ScoringFeature.State(
        centrePassTeamID: teamAID,
        firstBreakDurationSeconds: 240,
        gameID: UUID(),
        halfTimeDurationSeconds: 600,
        secondBreakDurationSeconds: 240,
        startedAt: Date(),
        teamA: ScoringFeature.Team(
          id: teamAID,
          colorHex: TeamColorPalette.blue,
          name: "Ravens"
        ),
        teamB: ScoringFeature.Team(
          id: teamBID,
          colorHex: TeamColorPalette.red,
          name: "Swifts"
        )
      )
    ) {
      ScoringFeature()
    }
  )
}
