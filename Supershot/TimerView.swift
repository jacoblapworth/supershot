import SwiftUI

struct TimerView: View {
  var clockPhase: ScoringFeature.ClockPhase
  var currentDurationSeconds: Int
  var elapsedSeconds: Int
  var isPeriodComplete: Bool
  var isShowingLastCentrePassBanner: Bool
  var isTimerRunning: Bool
  var period: Int
  var pauseTimerTapped: () -> Void
  var skipBreakTapped: () -> Void
  var startTimerTapped: () -> Void
  
  var body: some View {
    VStack(spacing: 12) {
      
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .font(.footnote)
          .foregroundStyle(.white)
        
        HStack {
          Text(formattedTime(timeRemainingSeconds))
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(.white)
          Spacer()
          if !isInitial {
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
        }
        
        ProgressView(
          value: Double(elapsedSeconds),
          total: Double(max(currentDurationSeconds, 1))
        )
        .animation(.linear, value: elapsedSeconds)
        .controlSize(.large)
      }
      
      if isInitial {
        startQuarterButton
      } else if isBreakPaused {
        Button(action: skipBreakTapped) {
          Label("Skip break", systemImage: "forward.end.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .fontWeight(.medium)
      }
    }
    .padding()
    .background(.black, in: RoundedRectangle(cornerRadius: 16))
  }
  
  private var isInitial: Bool {
    clockPhase == .quarter
    && !isTimerRunning
    && !isPeriodComplete
    && elapsedSeconds == 0
  }
  
  private var isBreakEnded: Bool {
    clockPhase == .breakTime && isPeriodComplete
  }
  
  private var isBreakPaused: Bool {
    clockPhase == .breakTime && !isTimerRunning && !isPeriodComplete
  }
  
  private var title: String {
    clockPhase == .breakTime ? "Break after quarter \(period)" : "Quarter \(period)"
  }
  
  private var startQuarterButton: some View {
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
    pauseTimerTapped: {},
    skipBreakTapped: {},
    startTimerTapped: {}
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
    pauseTimerTapped: {},
    skipBreakTapped: {},
    startTimerTapped: {}
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
    pauseTimerTapped: {},
    skipBreakTapped: {},
    startTimerTapped: {}
  )
  .padding()
}
