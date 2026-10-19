import AlarmClient
import AppSettings
import Database
import GameAnalysis
import GameCore
import GameServices
import PermissionsFeature
import PreviewSupport
import SharedModels
import SoundEffectsClient
import Styleguide
import SubscriptionClient
import SwiftUI
import WidgetSupport

package struct TimerView: View {
  package var canEditTime = false
  package var editTimeTapped: () -> Void = {}
  package var clockPhase: ScoringFeature.ClockPhase
  package var currentDurationSeconds: Int
  package var elapsedSeconds: Int
  package var isPeriodComplete: Bool
  package var isShowingLastCentrePassBanner: Bool
  package var isTimerRunning: Bool
  package var period: Int
  package var pauseTimerTapped: () -> Void
  package var skipBreakTapped: () -> Void
  package var startTimerTapped: () -> Void

  package var body: some View {
    VStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text(title)
            .font(.footnote)
            .foregroundStyle(.white)
          if canEditTime {
            #if os(macOS)
              Button("Edit remaining time", systemImage: "pencil", action: editTimeTapped)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Edit remaining time")
            #else
              Label("Edit", systemImage: "pencil")
                .font(.footnote)
                .labelStyle(.iconOnly)
                .foregroundStyle(.white.opacity(0.8))
            #endif
          }
        }
        HStack {
          HStack {
            Text(formattedTime(timeRemainingSeconds))
              .font(.system(size: 56, weight: .bold, design: .rounded))
              .monospacedDigit()
              .contentTransition(.numericText())
              .foregroundStyle(.white)

          }
          Spacer(minLength: 0)
          HStack(spacing: 4) {
            if isBreakPaused {
              TimerButton(type: .skip, action: skipBreakTapped)
            }
            if !isInitial && !isBreakNotStarted {
              TimerButton(type: isTimerRunning ? .pause : .play) {
                withAnimation {
                  if isTimerRunning {
                    pauseTimerTapped()
                  } else {
                    startTimerTapped()
                  }
                }
              }
              .disabled(
                isPeriodComplete
                  || (clockPhase == .quarter && isShowingLastCentrePassBanner)
              )
            }
          }
        }

        ProgressView(
          value: Double(elapsedSeconds),
          total: Double(max(currentDurationSeconds, 1))
        )
        .animation(.linear, value: elapsedSeconds)
        .controlSize(.large)
      }

      if isInitial || isBreakNotStarted {
        HStack {
          if isInitial {
            Button(action: startTimerTapped) {
              Label(
                isBreakEnded ? "Start Quarter \(period + 1)" : "Start Quarter \(period)",
                systemImage: "play.fill"
              )
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .fontWeight(.medium)
            .tint(.green)
            .disabled(clockPhase == .quarter && isShowingLastCentrePassBanner)
          }
          if isBreakNotStarted {
            Button("Start break", systemImage: "play.fill", action: startTimerTapped)
              .frame(maxWidth: .infinity)
              .buttonStyle(.borderedProminent)
              .controlSize(.large)
              .tint(.green)
          }
        }
      }
    }
    .padding()
    .background(.black, in: RoundedRectangle(cornerRadius: 24))
    #if os(iOS)
      .onTapGesture(perform: editTimeTapped)
      .accessibilityLabel("Edit remaining time")
    #endif
  }

  private var isInitial: Bool {
    clockPhase == .quarter
      && !isTimerRunning
      && !isPeriodComplete
      && elapsedSeconds == 0
  }

  private var isBreakNotStarted: Bool {
    isBreakPaused && elapsedSeconds == 0
  }

  private var isBreakEnded: Bool {
    clockPhase == .breakTime && isPeriodComplete
  }

  private var isBreakPaused: Bool {
    clockPhase == .breakTime && !isTimerRunning && !isPeriodComplete
  }

  private var title: String {
    clockPhase == .breakTime ? "Quarter \(period) break" : "Quarter \(period)"
  }

  private var timeRemainingSeconds: Int {
    withAnimation {
      max(currentDurationSeconds - elapsedSeconds, 0)
    }
  }

  private func formattedTime(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let seconds = seconds % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
  }

  package init(
    canEditTime: Bool = false, editTimeTapped: @escaping () -> Void = {},
    clockPhase: ScoringFeature.ClockPhase, currentDurationSeconds: Int, elapsedSeconds: Int,
    isPeriodComplete: Bool, isShowingLastCentrePassBanner: Bool, isTimerRunning: Bool, period: Int,
    pauseTimerTapped: @escaping () -> Void, skipBreakTapped: @escaping () -> Void,
    startTimerTapped: @escaping () -> Void
  ) {
    self.canEditTime = canEditTime
    self.editTimeTapped = editTimeTapped
    self.clockPhase = clockPhase
    self.currentDurationSeconds = currentDurationSeconds
    self.elapsedSeconds = elapsedSeconds
    self.isPeriodComplete = isPeriodComplete
    self.isShowingLastCentrePassBanner = isShowingLastCentrePassBanner
    self.isTimerRunning = isTimerRunning
    self.period = period
    self.pauseTimerTapped = pauseTimerTapped
    self.skipBreakTapped = skipBreakTapped
    self.startTimerTapped = startTimerTapped
  }
}

#Preview("Timer not started") {
  TimerView(
    clockPhase: .quarter,
    currentDurationSeconds: 480,
    elapsedSeconds: 0,
    isPeriodComplete: false,
    isShowingLastCentrePassBanner: false,
    isTimerRunning: false,
    period: 1,
    pauseTimerTapped: { print("Pause") },
    skipBreakTapped: { print("Skip") },
    startTimerTapped: { print("Start") }
  )
  .padding()
}

#Preview("Timer running") {
  TimerView(
    clockPhase: .quarter,
    currentDurationSeconds: 480,
    elapsedSeconds: 245,
    isPeriodComplete: false,
    isShowingLastCentrePassBanner: false,
    isTimerRunning: true,
    period: 1,
    pauseTimerTapped: { print("Pause") },
    skipBreakTapped: { print("Skip") },
    startTimerTapped: { print("Start") }
  )
  .padding()
}

#Preview("Timer complete") {
  TimerView(
    clockPhase: .quarter,
    currentDurationSeconds: 480,
    elapsedSeconds: 480,
    isPeriodComplete: true,
    isShowingLastCentrePassBanner: true,
    isTimerRunning: false,
    period: 1,
    pauseTimerTapped: { print("Pause") },
    skipBreakTapped: { print("Skip") },
    startTimerTapped: { print("Start") }
  )
  .padding()
}

#Preview("Break") {
  TimerView(
    editTimeTapped: { print("Edit") },
    clockPhase: .breakTime,
    currentDurationSeconds: 15 * 60,
    elapsedSeconds: 245,
    isPeriodComplete: false,
    isShowingLastCentrePassBanner: false,
    isTimerRunning: false,
    period: 2,
    pauseTimerTapped: { print("Pause") },
    skipBreakTapped: { print("Skip") },
    startTimerTapped: { print("Start") }
  )
  .padding()
}
