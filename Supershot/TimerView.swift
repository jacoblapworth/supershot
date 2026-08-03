import SwiftUI

struct TimerView: View {
  var clockPhase: ScoringFeature.ClockPhase
  var currentDurationSeconds: Int
  var elapsedSeconds: Int
  var isPeriodComplete: Bool
  var isShowingLastCentrePassBanner: Bool
  var isTimerRunning: Bool
  var pauseTimerTapped: () -> Void
  var startTimerTapped: () -> Void
  
  var body: some View {
    VStack(spacing: 16) {
      HStack {
        Text(formattedTime(timeRemainingSeconds))
          .font(.system(size: 56, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.white)
        Spacer()
        TimerButton(type: isTimerRunning ? .pause : .play) {
          withAnimation {
            if isTimerRunning {
              pauseTimerTapped()
            } else {
              startTimerTapped()
            }
          }
        }
        .disabled(isPeriodComplete)
      }
      
      ProgressView(
        value: Double(elapsedSeconds),
        total: Double(max(currentDurationSeconds, 1))
      )
      .controlSize(.large)
    }
    .padding()
    .background(.black, in: RoundedRectangle(cornerRadius: 16))
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
    startTimerTapped: {}
  )
  .padding()
}
