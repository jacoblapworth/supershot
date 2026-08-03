import SwiftUI

struct TimerView: View {
  var clockPhase: ScoringFeature.ClockPhase
  var currentDurationSeconds: Int
  var elapsedSeconds: Int
  var isPeriodComplete: Bool
  var isShowingLastCentrePassBanner: Bool
  var isTimerRunning: Bool
  var pauseTimerTapped: () -> Void
  var resumeTimerTapped: () -> Void
  var startTimerTapped: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Text(formattedTime(timeRemainingSeconds))
        .font(.system(size: 56, weight: .bold, design: .rounded))
        .monospacedDigit()
        .frame(maxWidth: .infinity)

      ProgressView(
        value: Double(elapsedSeconds),
        total: Double(max(currentDurationSeconds, 1))
      )

      if !isShowingLastCentrePassBanner || clockPhase == .breakTime {
        HStack {
          if isTimerRunning {
            Button {
              pauseTimerTapped()
            } label: {
              Label("Pause", systemImage: "pause.fill")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
          } else if elapsedSeconds == 0 {
            Button {
              startTimerTapped()
            } label: {
              Label("Start", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
          } else {
            Button {
              resumeTimerTapped()
            } label: {
              Label("Resume", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPeriodComplete)
          }
        }
        .controlSize(.large)
      }
    }
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
  }

  private var timeRemainingSeconds: Int {
    max(currentDurationSeconds - elapsedSeconds, 0)
  }

  private func formattedTime(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let seconds = seconds % 60
    return "\(minutes):\(String(format: "%02d", seconds))"
  }
}

#Preview("Timer not started") {
  TimerView(
    clockPhase: .quarter,
    currentDurationSeconds: 900,
    elapsedSeconds: 0,
    isPeriodComplete: false,
    isShowingLastCentrePassBanner: false,
    isTimerRunning: false,
    pauseTimerTapped: {},
    resumeTimerTapped: {},
    startTimerTapped: {}
  )
  .padding()
}

#Preview("Timer running") {
  TimerView(
    clockPhase: .quarter,
    currentDurationSeconds: 900,
    elapsedSeconds: 245,
    isPeriodComplete: false,
    isShowingLastCentrePassBanner: false,
    isTimerRunning: true,
    pauseTimerTapped: {},
    resumeTimerTapped: {},
    startTimerTapped: {}
  )
  .padding()
}

#Preview("Timer complete") {
  TimerView(
    clockPhase: .quarter,
    currentDurationSeconds: 900,
    elapsedSeconds: 900,
    isPeriodComplete: true,
    isShowingLastCentrePassBanner: true,
    isTimerRunning: false,
    pauseTimerTapped: {},
    resumeTimerTapped: {},
    startTimerTapped: {}
  )
  .padding()
}
