import Foundation
import SharedModels

/// Composed game progress. Clock transitions are pure; this projection applies their scoring consequences.
public nonisolated struct GameProgress: Equatable, Sendable {
  public var timing: GameTimingState
  public var scoring: GameScoringState

  public init(timing: GameTimingState, scoring: GameScoringState) {
    self.timing = timing
    self.scoring = scoring
  }

  public init(
    phaseIndex: Int,
    countdown: GameCountdown,
    isAwaitingCentrePassConfirmation: Bool,
    lateScoringPeriodNumber: Int? = nil,
    breakStartPolicy: BreakStartPolicy = .automatic
  ) {
    timing = GameTimingState(phaseIndex: phaseIndex, countdown: countdown, breakStartPolicy: breakStartPolicy)
    scoring = GameScoringState(
      isAwaitingCentrePassConfirmation: isAwaitingCentrePassConfirmation,
      lateScoringPeriodNumber: lateScoringPeriodNumber
    )
  }

  public var phaseIndex: Int {
    get { timing.phaseIndex }
    set { timing.phaseIndex = newValue }
  }

  public var countdown: GameCountdown {
    get { timing.countdown }
    set { timing.countdown = newValue }
  }

  public var isAwaitingCentrePassConfirmation: Bool {
    get { scoring.isAwaitingCentrePassConfirmation }
    set { scoring.isAwaitingCentrePassConfirmation = newValue }
  }

  public var lateScoringPeriodNumber: Int? {
    get { scoring.lateScoringPeriodNumber }
    set { scoring.lateScoringPeriodNumber = newValue }
  }

  public var breakStartPolicy: BreakStartPolicy {
    get { timing.breakStartPolicy }
    set { timing.breakStartPolicy = newValue }
  }

  public func isFinalPeriodComplete(in timeline: GameTimeline) -> Bool {
    timing.isFinalPeriodComplete(in: timeline)
  }

  public mutating func reconcile(in timeline: GameTimeline, now: Date) {
    apply(timing.reconcile(in: timeline, now: now))
  }

  public mutating func complete(in timeline: GameTimeline, boundary: Date) {
    apply(timing.complete(in: timeline, boundary: boundary))
  }

  public mutating func apply(_ transitions: [GameTimingTransition]) {
    for transition in transitions {
      switch transition {
      case let .periodCompleted(period, _, hasFollowingPeriod):
        lateScoringPeriodNumber = period.number
        if hasFollowingPeriod {
          isAwaitingCentrePassConfirmation = true
        }
      case .periodStarted:
        lateScoringPeriodNumber = nil
      case .breakCompleted:
        break
      }
    }
  }
}
