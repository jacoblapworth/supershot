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

package struct ScoringGameControls: View {
  package var canFinishGame: Bool
  package var canMoveToNextQuarter: Bool
  package var clockPhase: ScoringFeature.ClockPhase
  package var isShowingLastCentrePassBanner: Bool
  package var isTransitioningPeriod: Bool
  package var period: Int
  package var endQuarterTapped: () -> Void
  package var finishGameTapped: () -> Void
  package var skipBreakTapped: () -> Void

  package var body: some View {
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

  package init(
    canFinishGame: Bool, canMoveToNextQuarter: Bool, clockPhase: ScoringFeature.ClockPhase,
    isShowingLastCentrePassBanner: Bool, isTransitioningPeriod: Bool, period: Int,
    endQuarterTapped: @escaping () -> Void, finishGameTapped: @escaping () -> Void,
    skipBreakTapped: @escaping () -> Void
  ) {
    self.canFinishGame = canFinishGame
    self.canMoveToNextQuarter = canMoveToNextQuarter
    self.clockPhase = clockPhase
    self.isShowingLastCentrePassBanner = isShowingLastCentrePassBanner
    self.isTransitioningPeriod = isTransitioningPeriod
    self.period = period
    self.endQuarterTapped = endQuarterTapped
    self.finishGameTapped = finishGameTapped
    self.skipBreakTapped = skipBreakTapped
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
