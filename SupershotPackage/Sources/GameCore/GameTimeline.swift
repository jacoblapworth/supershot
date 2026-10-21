import Foundation
import SharedModels

/// Validates the stored schedule and derives its immutable clock timeline.
public nonisolated struct GameTimeline: Equatable, Sendable {
  public let periods: [GamePeriod]
  public let phases: [GamePhase]

  public init?(periods: [GamePeriod]) {
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
    phases = periods.flatMap { period in
      let reference = GamePeriodReference(id: period.id, number: period.number)
      var phases: [GamePhase] = [.period(reference, durationSeconds: period.durationSeconds)]
      if let duration = period.breakAfterDurationSeconds, duration > 0 {
        phases.append(.breakTime(after: reference, durationSeconds: duration))
      }
      return phases
    }
  }

  public func phase(at index: Int) -> GamePhase? {
    phases.indices.contains(index) ? phases[index] : nil
  }

  public func activePlayingPeriod(at index: Int) -> GamePeriod? {
    guard case let .period(reference, _) = phase(at: index) else { return nil }
    return periods.first { $0.id == reference.id }
  }

  public func precedingPeriod(at index: Int) -> GamePeriod? {
    guard let phase = phase(at: index) else { return nil }
    if phase.isBreak {
      return periods.first { $0.id == phase.associatedPeriod.id }
    }
    return periods.first { $0.number == phase.associatedPeriod.number - 1 }
  }
}
