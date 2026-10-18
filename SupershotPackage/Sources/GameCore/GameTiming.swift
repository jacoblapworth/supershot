import Foundation
import SharedModels

/// Facts about clock transitions. Scoring consequences are applied by game coordination.
nonisolated public enum GameTimingTransition: Equatable, Sendable {
  case periodCompleted(GamePeriodReference, boundary: Date, hasFollowingPeriod: Bool)
  case breakCompleted(GamePeriodReference, boundary: Date)
  case periodStarted(GamePeriodReference)
}

nonisolated public enum GameTimingCommand: Equatable, Sendable {
  case startOrResume
  case pause
  case skip
  case setRemainingTime(Int)
}

nonisolated public struct GameTimingResult: Equatable, Sendable {
  public enum Status: Equatable, Sendable { case applied, unchanged, rejected }
  public var status: Status
  public var transitions: [GameTimingTransition] = []

  public init(status: Status, transitions: [GameTimingTransition] = []) {
    self.status = status
    self.transitions = transitions
  }
}

/// Pure clock state: no goals, centre-pass ownership, persistence, or presentations.
nonisolated public struct GameTimingState: Equatable, Sendable {
  public var phaseIndex: Int
  public var countdown: GameCountdown
  public var breakStartPolicy = BreakStartPolicy.automatic

  public func isFinalPeriodComplete(in timeline: GameTimeline) -> Bool {
    guard let phase = timeline.phase(at: phaseIndex) else { return false }
    return phaseIndex == timeline.phases.count - 1
      && countdown.projection(durationSeconds: phase.durationSeconds).status == .complete
      && !countdown.isRunning
  }

  @discardableResult
  mutating public func reconcile(in timeline: GameTimeline, now: Date) -> [GameTimingTransition] {
    guard timeline.phase(at: phaseIndex) != nil else { return [] }
    var transitions: [GameTimingTransition] = []
    while let boundary = countdown.endsAt, boundary <= now {
      transitions += complete(in: timeline, boundary: boundary)
    }
    countdown.elapsedSeconds =
      countdown.projection(
        durationSeconds: timeline.phases[phaseIndex].durationSeconds, now: now
      ).elapsedSeconds
    return transitions
  }

  @discardableResult
  mutating public func complete(in timeline: GameTimeline, boundary: Date) -> [GameTimingTransition]
  {
    guard let phase = timeline.phase(at: phaseIndex), !isFinalPeriodComplete(in: timeline) else {
      return []
    }
    let hasNext = phaseIndex + 1 < timeline.phases.count
    let transition: GameTimingTransition =
      phase.isPlayingPeriod
      ? .periodCompleted(phase.associatedPeriod, boundary: boundary, hasFollowingPeriod: hasNext)
      : .breakCompleted(phase.associatedPeriod, boundary: boundary)
    countdown = GameCountdown(elapsedSeconds: phase.durationSeconds)
    guard hasNext else { return [transition] }
    phaseIndex += 1
    countdown = GameCountdown()
    let next = timeline.phases[phaseIndex]
    // A playing period always waits for explicit start, including when a break is omitted.
    if next.isBreak, breakStartPolicy == .automatic {
      countdown.endsAt = boundary.addingTimeInterval(TimeInterval(next.durationSeconds))
    }
    return [transition]
  }

  mutating public func apply(
    _ command: GameTimingCommand, in timeline: GameTimeline,
    expectedPhaseIndex: Int?, now: Date
  ) -> GameTimingResult {
    guard let phase = timeline.phase(at: phaseIndex),
      expectedPhaseIndex == nil || expectedPhaseIndex == phaseIndex
    else { return GameTimingResult(status: .rejected) }
    switch command {
    case .startOrResume:
      guard !countdown.isRunning,
        let endsAt = countdown.endDate(durationSeconds: phase.durationSeconds, now: now)
      else { return GameTimingResult(status: .unchanged) }
      countdown.endsAt = endsAt
      return GameTimingResult(
        status: .applied,
        transitions: phase.isPlayingPeriod ? [.periodStarted(phase.associatedPeriod)] : [])
    case .pause:
      guard countdown.isRunning else { return GameTimingResult(status: .unchanged) }
      countdown.elapsedSeconds =
        countdown.projection(durationSeconds: phase.durationSeconds, now: now).elapsedSeconds
      countdown.endsAt = nil
      return GameTimingResult(status: .applied)
    case .skip:
      guard !isFinalPeriodComplete(in: timeline) else {
        return GameTimingResult(status: .unchanged)
      }
      return GameTimingResult(status: .applied, transitions: complete(in: timeline, boundary: now))
    case .setRemainingTime(let seconds):
      guard !countdown.isRunning, countdown.elapsedSeconds < phase.durationSeconds,
        (1...phase.durationSeconds).contains(seconds)
      else { return GameTimingResult(status: .rejected) }
      countdown.elapsedSeconds = phase.durationSeconds - seconds
      return GameTimingResult(status: .applied)
    }
  }

  public init(
    phaseIndex: Int, countdown: GameCountdown,
    breakStartPolicy: BreakStartPolicy = BreakStartPolicy.automatic
  ) {
    self.phaseIndex = phaseIndex
    self.countdown = countdown
    self.breakStartPolicy = breakStartPolicy
  }
}

extension Game {
  nonisolated public var timing: GameTimingState {
    get {
      GameTimingState(
        phaseIndex: currentPhaseIndex, countdown: countdown, breakStartPolicy: breakStartPolicy)
    }
    set {
      currentPhaseIndex = newValue.phaseIndex
      countdown = newValue.countdown
      breakStartPolicy = newValue.breakStartPolicy
    }
  }
}
