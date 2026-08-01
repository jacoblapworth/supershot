import Foundation

nonisolated enum GameTimerMath {
  static func elapsedSeconds(
    durationSeconds: Int,
    persistedElapsedSeconds: Int,
    timerEndsAt: Date?,
    now: Date
  ) -> Int {
    let durationSeconds = max(durationSeconds, 0)
    let persistedElapsedSeconds = min(
      max(persistedElapsedSeconds, 0),
      durationSeconds
    )
    guard let timerEndsAt else { return persistedElapsedSeconds }
    let remainingSeconds = min(
      max(Int(ceil(timerEndsAt.timeIntervalSince(now))), 0),
      durationSeconds
    )
    return durationSeconds - remainingSeconds
  }

  static func endDate(
    durationSeconds: Int,
    elapsedSeconds: Int,
    now: Date
  ) -> Date? {
    let remainingSeconds = max(durationSeconds - elapsedSeconds, 0)
    guard remainingSeconds > 0 else { return nil }
    return now.addingTimeInterval(TimeInterval(remainingSeconds))
  }
}
