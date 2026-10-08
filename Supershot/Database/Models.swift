//
//  Models.swift
//  Supershot
//
//  Created by J on 16/09/2026.
//

import Foundation

/// Stable identity and display number of a playing period in a derived phase.
nonisolated struct GamePeriodReference: Equatable, Hashable, Codable, Sendable {
  let id: UUID
  let number: Int
}

/// A clock segment derived from the game's persisted periods.
nonisolated enum GamePhase: Equatable, Hashable, Codable, Sendable {
  case period(GamePeriodReference, durationSeconds: Int)
  case breakTime(after: GamePeriodReference, durationSeconds: Int)

  var durationSeconds: Int {
    switch self {
    case let .period(_, duration), let .breakTime(_, duration): duration
    }
  }

  /// For a break, this identifies the period that precedes it.
  var associatedPeriod: GamePeriodReference {
    switch self {
    case let .period(period, _), let .breakTime(period, _): period
    }
  }

  var isBreak: Bool {
    if case .breakTime = self { true } else { false }
  }

  var isPlayingPeriod: Bool {
    if case .period = self { true } else { false }
  }
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
    if phase.isPlayingPeriod, timer.status == .running, !isAwaitingCentrePassConfirmation {
      return .livePeriod(number: phase.associatedPeriod.number)
    }
    guard let completed = lateScoringPeriodNumber else { return nil }
    let isCompletedPeriod = phase.isPlayingPeriod && phase.associatedPeriod.number == completed && timer.status == .complete
    let isFollowingBreak = phase.isBreak && phase.associatedPeriod.number == completed
    let isWaitingPeriod = phase.isPlayingPeriod && phase.associatedPeriod.number == completed + 1
      && timer.status == .paused && timer.elapsedSeconds == 0
    return isCompletedPeriod || isFollowingBreak || isWaitingPeriod
      ? .completedPeriod(number: completed) : nil
  }
}
