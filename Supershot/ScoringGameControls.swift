import SwiftUI

struct ScoringGameControls: View {
  var canContinueToNextQuarter: Bool
  var canFinishGame: Bool
  var canMoveToNextQuarter: Bool
  var clockPhase: ScoringFeature.ClockPhase
  var isShowingLastCentrePassBanner: Bool
  var isTransitioningPeriod: Bool
  var period: Int
  var continueToNextQuarterTapped: () -> Void
  var endQuarterTapped: () -> Void
  var finishGameTapped: () -> Void
  var skipBreakTapped: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      if canContinueToNextQuarter {
        Button {
          continueToNextQuarterTapped()
        } label: {
          Label("Continue to quarter \(period + 1)", systemImage: "arrow.forward.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      } else if clockPhase == .break {
        Button {
          skipBreakTapped()
        } label: {
          Label("Skip break", systemImage: "forward.end.fill")
            .frame(maxWidth: .infinity)
        }
        .fontWeight(.medium)
        .controlSize(.large)
        .buttonStyle(.bordered)
        .disabled(isShowingLastCentrePassBanner || isTransitioningPeriod)
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
    canContinueToNextQuarter: false,
    canFinishGame: false,
    canMoveToNextQuarter: true,
    clockPhase: .quarter,
    isShowingLastCentrePassBanner: false,
    isTransitioningPeriod: false,
    period: 1,
    continueToNextQuarterTapped: {},
    endQuarterTapped: {},
    finishGameTapped: {},
    skipBreakTapped: {}
  )
  .padding()
}

#Preview("Continue after break") {
  ScoringGameControls(
    canContinueToNextQuarter: true,
    canFinishGame: false,
    canMoveToNextQuarter: false,
    clockPhase: .break,
    isShowingLastCentrePassBanner: false,
    isTransitioningPeriod: false,
    period: 2,
    continueToNextQuarterTapped: {},
    endQuarterTapped: {},
    finishGameTapped: {},
    skipBreakTapped: {}
  )
  .padding()
}

#Preview("Finish game") {
  ScoringGameControls(
    canContinueToNextQuarter: false,
    canFinishGame: true,
    canMoveToNextQuarter: false,
    clockPhase: .quarter,
    isShowingLastCentrePassBanner: false,
    isTransitioningPeriod: false,
    period: 4,
    continueToNextQuarterTapped: {},
    endQuarterTapped: {},
    finishGameTapped: {},
    skipBreakTapped: {}
  )
  .padding()
}
