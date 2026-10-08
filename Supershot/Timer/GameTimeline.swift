import Foundation

/// Validates the stored schedule and derives its immutable clock timeline.
nonisolated struct GameTimeline: Equatable, Sendable {
  let periods: [GamePeriod]
  let phases: [GamePhase]

  init?(periods: [GamePeriod]) {
    let periods = periods.sorted { $0.position < $1.position }
    guard let first = periods.first,
      Set(periods.map(\.id)).count == periods.count,
      periods.enumerated().allSatisfy({ position, period in
        period.gameID == first.gameID && period.position == position
          && period.durationSeconds > 0 && (period.breakAfterDurationSeconds ?? 0) >= 0
      }),
      (periods.last?.breakAfterDurationSeconds ?? 0) == 0
    else { return nil }

    self.periods = periods
    self.phases = periods.flatMap { period in
      let reference = GamePeriodReference(id: period.id, number: period.number)
      var phases: [GamePhase] = [.period(reference, durationSeconds: period.durationSeconds)]
      if let duration = period.breakAfterDurationSeconds, duration > 0 {
        phases.append(.breakTime(after: reference, durationSeconds: duration))
      }
      return phases
    }
  }

  func phase(at index: Int) -> GamePhase? {
    phases.indices.contains(index) ? phases[index] : nil
  }

  func activePlayingPeriod(at index: Int) -> GamePeriod? {
    guard case let .period(reference, _) = phase(at: index) else { return nil }
    return periods.first { $0.id == reference.id }
  }

  func precedingPeriod(at index: Int) -> GamePeriod? {
    guard let phase = phase(at: index) else { return nil }
    if phase.isBreak {
      return periods.first { $0.id == phase.associatedPeriod.id }
    }
    return periods.first { $0.number == phase.associatedPeriod.number - 1 }
  }

  func scoringPeriod(for context: GameScoringContext) -> GamePeriod? {
    periods.first { $0.number == context.periodNumber }
  }
}

/// Timing transitions are independent of storage, UI, and system presentations.
nonisolated struct GameProgress: Equatable, Sendable {
  var phaseIndex: Int
  var countdown: GameCountdown
  var isAwaitingCentrePassConfirmation: Bool
  var lateScoringPeriodNumber: Int?

  func isFinalPeriodComplete(in timeline: GameTimeline) -> Bool {
    guard let phase = timeline.phase(at: phaseIndex) else { return false }
    return phaseIndex == timeline.phases.count - 1
      && countdown.projection(durationSeconds: phase.durationSeconds).status == .complete
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
    if phase.isPlayingPeriod { lateScoringPeriodNumber = phase.associatedPeriod.number }
    guard phaseIndex + 1 < timeline.phases.count else { return }
    if phase.isPlayingPeriod { isAwaitingCentrePassConfirmation = true }
    phaseIndex += 1
    countdown = GameCountdown()
    let next = timeline.phases[phaseIndex]
    // Playing periods always wait for an explicit start, even when a break is omitted.
    if next.isBreak {
      countdown.endsAt = boundary.addingTimeInterval(TimeInterval(next.durationSeconds))
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
    if phase.isPlayingPeriod, let next = timeline.phase(at: progress.phaseIndex + 1), next.isBreak, next.durationSeconds > 0 {
      result.append(Self(
        date: endsAt.addingTimeInterval(TimeInterval(next.durationSeconds)),
        phase: next, phaseIndex: progress.phaseIndex + 1
      ))
    }
    return result
  }
}
