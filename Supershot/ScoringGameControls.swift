import SwiftUI

struct ScoringGameControls: View {
  var canFinishGame: Bool
  var canMoveToNextQuarter: Bool
  var clockPhase: ScoringFeature.ClockPhase
  var isShowingLastCentrePassBanner: Bool
  var isTransitioningPeriod: Bool
  var period: Int
  var endQuarterTapped: () -> Void
  var finishGameTapped: () -> Void
  var skipBreakTapped: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      if clockPhase == .breakTime {
        Button {
          skipBreakTapped()
        } label: {
          Label("Skip break", systemImage: "forward.end.fill")
            .frame(maxWidth: .infinity)
        }
        .fontWeight(.medium)
        .controlSize(.large)
        .buttonStyle(.bordered)
        .disabled(isTransitioningPeriod)
      } else if canMoveToNextQuarter {
        Button {
          endQuarterTapped()
        } label: {
          Label("End quarter", systemImage: "forward.end.fill")
            .frame(maxWidth: .infinity)
        }
        .fontWeight(.medium)
        .controlSize(.large)
        .buttonStyle(.bordered)
      }

      if canFinishGame {
        Button {
          finishGameTapped()
        } label: {
          Label("Finish game", systemImage: "flag.checkered")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      }
    }
  }
}

#Preview("End quarter") {
  ScoringGameControls(
    canFinishGame: false,
    canMoveToNextQuarter: true,
    clockPhase: .quarter,
    isShowingLastCentrePassBanner: false,
    isTransitioningPeriod: false,
    period: 1,
    endQuarterTapped: {},
    finishGameTapped: {},
    skipBreakTapped: {}
  )
  .padding()
}

#Preview("Continue after break") {
  ScoringGameControls(
    canFinishGame: false,
    canMoveToNextQuarter: false,
    clockPhase: .breakTime,
    isShowingLastCentrePassBanner: false,
    isTransitioningPeriod: false,
    period: 2,
    endQuarterTapped: {},
    finishGameTapped: {},
    skipBreakTapped: {}
  )
  .padding()
}

#Preview("Finish game") {
  ScoringGameControls(
    canFinishGame: true,
    canMoveToNextQuarter: false,
    clockPhase: .quarter,
    isShowingLastCentrePassBanner: false,
    isTransitioningPeriod: false,
    period: 4,
    endQuarterTapped: {},
    finishGameTapped: {},
    skipBreakTapped: {}
  )
  .padding()
}
