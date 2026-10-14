import Foundation

/// Composed game progress. Clock transitions are pure; this projection applies their scoring consequences.
nonisolated struct GameProgress: Equatable, Sendable {
  var timing: GameTimingState
  var scoring: GameScoringState

  init(timing: GameTimingState, scoring: GameScoringState) {
    self.timing = timing
    self.scoring = scoring
  }

  init(
    phaseIndex: Int, countdown: GameCountdown, isAwaitingCentrePassConfirmation: Bool,
    lateScoringPeriodNumber: Int? = nil, breakStartPolicy: BreakStartPolicy = .automatic
  ) {
    timing = GameTimingState(
      phaseIndex: phaseIndex, countdown: countdown, breakStartPolicy: breakStartPolicy)
    scoring = GameScoringState(
      isAwaitingCentrePassConfirmation: isAwaitingCentrePassConfirmation,
      lateScoringPeriodNumber: lateScoringPeriodNumber)
  }

  var phaseIndex: Int {
    get { timing.phaseIndex }
    set { timing.phaseIndex = newValue }
  }
  var countdown: GameCountdown {
    get { timing.countdown }
    set { timing.countdown = newValue }
  }
  var isAwaitingCentrePassConfirmation: Bool {
    get { scoring.isAwaitingCentrePassConfirmation }
    set { scoring.isAwaitingCentrePassConfirmation = newValue }
  }
  var lateScoringPeriodNumber: Int? {
    get { scoring.lateScoringPeriodNumber }
    set { scoring.lateScoringPeriodNumber = newValue }
  }
  var breakStartPolicy: BreakStartPolicy {
    get { timing.breakStartPolicy }
    set { timing.breakStartPolicy = newValue }
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
