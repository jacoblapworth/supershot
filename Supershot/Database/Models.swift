//
//  Models.swift
//  Supershot
//
//  Created by J on 16/09/2026.
//

import Foundation

nonisolated enum GameTeamSlot: String, Codable, Hashable, Sendable {
  case teamA
  case teamB

  var opponent: Self { self == .teamA ? .teamB : .teamA }

  func courtLeftTeam(periodNumber: Int) -> Self {
    periodNumber.isMultiple(of: 2) ? opponent : self
  }
}

/// Phase of a game
nonisolated enum GamePhase: Equatable, Hashable, Codable, Sendable {
  case period(number: Int, durationSeconds: Int)
  case breakTime(afterPeriod: Int, durationSeconds: Int)
  
  var durationSeconds: Int {
    switch self {
    case let .period(_, durationSeconds), let .breakTime(_, durationSeconds):
      max(durationSeconds, 0)
    }
  }
  
  var periodNumber: Int {
    switch self {
    case let .period(number, _):
      number
    case let .breakTime(afterQuarter, _):
      afterQuarter
    }
  }
  
  var isBreak: Bool {
    switch self {
    case .period: false
    case .breakTime: true
    }
  }
  
  var isQuarter: Bool { !isBreak }
}

/// A countdown's persisted values. All time-dependent facts come from one projection.
nonisolated struct GameCountdown: Equatable, Hashable, Sendable {
  var elapsedSeconds = 0
  var endsAt: Date?
  var isRunning: Bool { endsAt != nil }

  enum Status: Equatable, Sendable {
    case paused
    case running
    case complete
  }

  struct Projection: Equatable, Sendable {
    var elapsedSeconds: Int
    var remainingSeconds: Int
    var status: Status
  }

  func projection(durationSeconds: Int, now: Date? = nil) -> Projection {
    let duration = max(durationSeconds, 0)
    let elapsed: Int
    if let endsAt, let now {
      let remaining = min(max(ceil(endsAt.timeIntervalSince(now)), 0), Double(duration))
      elapsed = duration - Int(remaining)
    } else {
      elapsed = min(max(elapsedSeconds, 0), duration)
    }
    return Projection(
      elapsedSeconds: elapsed,
      remainingSeconds: duration - elapsed,
      status: elapsed >= duration ? .complete : endsAt == nil ? .paused : .running
    )
  }

  func endDate(durationSeconds: Int, now: Date) -> Date? {
    let remaining = projection(durationSeconds: durationSeconds).remainingSeconds
    return remaining > 0 ? now.addingTimeInterval(TimeInterval(remaining)) : nil
  }
}

/// An immutable ordered timeline. Optional breaks may be omitted, but periods stay contiguous.
nonisolated struct GameTimeline: Equatable, Sendable {
  let phases: [GamePhase]

  init?(phases: [GamePhase]) {
    guard !phases.isEmpty else { return nil }
    var nextPeriod = 1
    var followsPeriod = false
    for phase in phases {
      switch phase {
      case let .period(number, duration):
        guard number == nextPeriod, duration > 0 else { return nil }
        nextPeriod += 1
        followsPeriod = true
      case let .breakTime(afterPeriod, duration):
        guard followsPeriod, afterPeriod == nextPeriod - 1, duration >= 0 else { return nil }
        followsPeriod = false
      }
    }
    guard phases.last?.isQuarter == true else { return nil }
    self.phases = phases
  }

  func phase(at index: Int) -> GamePhase? {
    phases.indices.contains(index) ? phases[index] : nil
  }
}

/// Timing transitions are independent of storage, UI, and system presentations.
nonisolated struct GameProgress: Equatable, Sendable {
  var phaseIndex: Int
  var countdown: GameCountdown
  var isAwaitingCentrePassConfirmation: Bool
  var lateScoringPeriodNumber: Int?

  func isFinalPeriodComplete(in timeline: GameTimeline) -> Bool {
    phaseIndex == timeline.phases.count - 1
      && countdown.projection(durationSeconds: timeline.phases[phaseIndex].durationSeconds).status == .complete
      && !countdown.isRunning
  }

  mutating func reconcile(in timeline: GameTimeline, now: Date) {
    guard timeline.phase(at: phaseIndex) != nil else { return }
    while let boundary = countdown.endsAt, boundary <= now {
      complete(in: timeline, boundary: boundary)
    }
    countdown.elapsedSeconds = countdown.projection(
      durationSeconds: timeline.phases[phaseIndex].durationSeconds, now: now
    ).elapsedSeconds
  }

  mutating func complete(in timeline: GameTimeline, boundary: Date) {
    guard let phase = timeline.phase(at: phaseIndex) else { return }
    countdown = GameCountdown(elapsedSeconds: phase.durationSeconds)
    if phase.isQuarter { lateScoringPeriodNumber = phase.periodNumber }
    guard phaseIndex + 1 < timeline.phases.count else { return }
    if phase.isQuarter { isAwaitingCentrePassConfirmation = true }
    phaseIndex += 1
    countdown = GameCountdown()
    let next = timeline.phases[phaseIndex]
    // Playing periods always wait for an explicit start, even when a break is omitted.
    if next.isBreak {
      if next.durationSeconds > 0 {
        countdown.endsAt = boundary.addingTimeInterval(TimeInterval(next.durationSeconds))
      } else {
        complete(in: timeline, boundary: boundary)
      }
    }
  }
}

nonisolated struct ScheduledGameAlarm: Equatable, Sendable {
  var date: Date
  var phase: GamePhase
  var phaseIndex: Int

  static func plan(timeline: GameTimeline, progress: GameProgress) -> [Self] {
    guard let phase = timeline.phase(at: progress.phaseIndex), let endsAt = progress.countdown.endsAt else {
      return []
    }
    var result = [Self(date: endsAt, phase: phase, phaseIndex: progress.phaseIndex)]
    if phase.isQuarter, let next = timeline.phase(at: progress.phaseIndex + 1), next.isBreak, next.durationSeconds > 0 {
      result.append(Self(
        date: endsAt.addingTimeInterval(TimeInterval(next.durationSeconds)),
        phase: next, phaseIndex: progress.phaseIndex + 1
      ))
    }
    return result
  }
}

/// Attribution is separate from the phase whose clock is currently on screen.
nonisolated enum GameScoringContext: Equatable, Sendable {
  case livePeriod(number: Int)
  case completedPeriod(number: Int)

  var periodNumber: Int {
    switch self {
    case let .livePeriod(number), let .completedPeriod(number): number
    }
  }

  var isLate: Bool {
    if case .completedPeriod = self { true } else { false }
  }

  static func resolve(
    phase: GamePhase,
    countdown: GameCountdown,
    isAwaitingCentrePassConfirmation: Bool,
    lateScoringPeriodNumber: Int?,
    now: Date? = nil
  ) -> Self? {
    let timer = countdown.projection(durationSeconds: phase.durationSeconds, now: now)
    if phase.isQuarter, timer.status == .running, !isAwaitingCentrePassConfirmation {
      return .livePeriod(number: phase.periodNumber)
    }
    guard let completed = lateScoringPeriodNumber else { return nil }
    let isCompletedPeriod = phase.isQuarter && phase.periodNumber == completed && timer.status == .complete
    let isFollowingBreak = phase.isBreak && phase.periodNumber == completed
    let isWaitingPeriod = phase.isQuarter && phase.periodNumber == completed + 1
      && timer.status == .paused && timer.elapsedSeconds == 0
    return isCompletedPeriod || isFollowingBreak || isWaitingPeriod
      ? .completedPeriod(number: completed) : nil
  }
}
