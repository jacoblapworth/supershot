import AlarmClient
import AppSettings
import AppUI
import ComposableArchitecture
import Database
import Foundation
import GameAnalysis
import GameCore
import GameServices
import PermissionsFeature
import PreviewSupport
import SharedModels
import SoundEffectsClient
import SubscriptionClient
import SwiftUI
import UI

package extension ScoringFeature.Team {
  static let previewRavens = Self(
    id: UUID(3),
    bibColor: ColorPalette.green,
    name: "Foxes"
  )
  static let previewSwifts = Self(
    id: UUID(4),
    bibColor: ColorPalette.orange,
    name: "Owls"
  )
}

package extension ScoringFeature.State {
  static var previewQuarter: Self {
    Self(
      centrePassTeamID: ScoringFeature.Team.previewRavens.id,
      currentPhaseIndex: 2,
      gameID: UUID(11),
      periods: MockGameData.periods(gameID: UUID(11), idOffset: 1010),
      startedAt: Date(timeIntervalSince1970: 1000),
      teamA: .previewRavens,
      teamB: .previewSwifts,
      teamBScore: 1
    )
  }

  static var previewQuarterComplete: Self {
    var state = previewQuarter
    state.canUndo = true
    state.elapsedSeconds = state.currentDurationSeconds
    state.isShowingLastCentrePassBanner = true
    state.teamAScore = 38
    state.teamBScore = 38
    return state
  }

  static var previewBreak: Self {
    var state = previewQuarter
    state.currentPhaseIndex = 3
    state.lateScoringPeriodNumber = 2
    state.isShowingLastCentrePassBanner = true
    state.elapsedSeconds = 0
    state.teamAScore = 19
    state.teamBScore = 19
    return state
  }
}

@MainActor
package func scoringPreviewStore(
  _ state: ScoringFeature.State
) -> StoreOf<ScoringFeature> {
  Store(initialState: state) {
    ScoringFeature()
  } withDependencies: {
    // Screen previews should retain their selected scenario instead of reconciling
    // with a different debug game or starting an endless clock effect.
    $0.gameTimer.reconcile = { _ in throw CancellationError() }
  }
}

/// Fixed clock values keep previews reproducible and independent of wall-clock time.
package enum ScoringPreviewScenario: String, CaseIterable, Identifiable {
  case ready = "Start game"
  case running = "Quarter running"
  case paused = "Quarter paused"
  case nextQuarter = "Start next quarter"
  case manualBreak = "Break awaiting start"
  case runningBreak = "Break running"
  case pausedBreak = "Break paused"
  case confirmation = "Centre-pass confirmation"
  case savingConfirmation = "Saving centre pass"
  case starting = "Starting clock"
  case pausing = "Pausing clock"
  case skipping = "Skipping break"
  case complete = "End game"
  case finishing = "Ending game"
  case failed = "Action failed"

  package var id: Self {
    self
  }

  package var state: ScoringFeature.State {
    var state = ScoringFeature.State.previewQuarter
    state.startedAt = Date(timeIntervalSince1970: 1000)
    state.currentPhaseIndex = 0
    state.teamAScore = 12
    state.teamBScore = 10
    switch self {
    case .ready, .starting:
      state.startedAt = nil
      state.teamAScore = 0
      state.teamBScore = 0
      if self == .starting {
        state.operation = .starting(phaseIndex: 0)
      }
    case .running:
      state.elapsedSeconds = 120
      state.timerEndsAt = Date(timeIntervalSince1970: 1360)
    case .paused, .pausing:
      state.elapsedSeconds = 120
      if self == .pausing {
        state.operation = .pausing(phaseIndex: 0)
      }
    case .nextQuarter:
      state.currentPhaseIndex = 2
      state.lateScoringPeriodNumber = 1
    case .manualBreak, .runningBreak, .pausedBreak, .skipping, .confirmation, .savingConfirmation:
      state.currentPhaseIndex = 1
      state.lateScoringPeriodNumber = 1
      if self == .runningBreak || self == .confirmation || self == .savingConfirmation {
        state.elapsedSeconds = 15
        state.timerEndsAt = Date(timeIntervalSince1970: 1045)
      }
      if self == .pausedBreak {
        state.elapsedSeconds = 15
      }
      if self == .confirmation || self == .savingConfirmation {
        state.isShowingLastCentrePassBanner = true
      }
      if self == .savingConfirmation {
        state.operation = .confirmingCentrePass(period: 1)
      }
      if self == .skipping {
        state.operation = .skipping(phaseIndex: 1)
      }
    case .complete, .finishing:
      state.currentPhaseIndex = state.timeline.phases.count - 1
      state.elapsedSeconds = state.currentDurationSeconds
      state.lateScoringPeriodNumber = state.period
      if self == .finishing {
        state.operation = .finishing
      }
    case .failed:
      state.alert = .operationFailed("Couldn’t start clock")
    }
    return state
  }
}
