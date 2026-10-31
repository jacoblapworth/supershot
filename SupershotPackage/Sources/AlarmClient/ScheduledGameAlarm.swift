import Database
import Foundation
import GameCore
import SharedModels

public nonisolated struct ScheduledGameAlarm: Equatable, Sendable {
  public var date: Date
  public var phase: GamePhase
  public var phaseIndex: Int

  public static func plan(timeline: GameTimeline, progress: GameTimingState) -> [Self] {
    guard let phase = timeline.phase(at: progress.phaseIndex),
          let endsAt = progress.countdown.endsAt
    else {
      return []
    }
    var result = [Self(date: endsAt, phase: phase, phaseIndex: progress.phaseIndex)]
    if progress.breakStartPolicy == .automatic, phase.isPlayingPeriod,
       let next = timeline.phase(at: progress.phaseIndex + 1), next.isBreak, next.durationSeconds > 0
    {
      result.append(Self(
        date: endsAt.addingTimeInterval(TimeInterval(next.durationSeconds)),
        phase: next,
        phaseIndex: progress.phaseIndex + 1
      ))
    }
    return result
  }

  public init(date: Date, phase: GamePhase, phaseIndex: Int) {
    self.date = date
    self.phase = phase
    self.phaseIndex = phaseIndex
  }
}
