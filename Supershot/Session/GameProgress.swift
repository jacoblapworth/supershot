import Foundation

/// Composed game progress. Clock transitions are pure; this projection applies their scoring consequences.
nonisolated struct GameProgress: Equatable, Sendable {
  var phaseIndex: Int
  var countdown: GameCountdown
  var isAwaitingCentrePassConfirmation: Bool
  var lateScoringPeriodNumber: Int?
  var breakStartPolicy = BreakStartPolicy.automatic

  var timing: GameTimingState {
    get {
      GameTimingState(
        phaseIndex: phaseIndex, countdown: countdown, breakStartPolicy: breakStartPolicy)
    }
    set {
      phaseIndex = newValue.phaseIndex
      countdown = newValue.countdown
      breakStartPolicy = newValue.breakStartPolicy
    }
  }

  func isFinalPeriodComplete(in timeline: GameTimeline) -> Bool {
    timing.isFinalPeriodComplete(in: timeline)
  }

  mutating func reconcile(in timeline: GameTimeline, now: Date) {
    apply(timing.reconcile(in: timeline, now: now))
  }

  mutating func complete(in timeline: GameTimeline, boundary: Date) {
    apply(timing.complete(in: timeline, boundary: boundary))
  }

  mutating func apply(_ transitions: [GameTimingTransition]) {
    for transition in transitions {
      switch transition {
      case .periodCompleted(let period, _, let hasFollowingPeriod):
        lateScoringPeriodNumber = period.number
        if hasFollowingPeriod { isAwaitingCentrePassConfirmation = true }
      case .periodStarted:
        lateScoringPeriodNumber = nil
      case .breakCompleted:
        break
      }
    }
  }
}
