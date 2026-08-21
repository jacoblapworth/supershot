import DependenciesTestSupport
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import Supershot

@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
struct SupershotTestSuite {}

nonisolated func clearDatabase(_ database: any DatabaseWriter) throws {
  try database.write { db in
    try Goal.delete().execute(db)
    try Game.delete().execute(db)
    try Team.delete().execute(db)
  }
}

nonisolated func testGamePeriodID(
  gameID: Game.ID,
  position: Int
) -> GamePeriod.ID {
  let value = gameID.uuid
  return UUID(
    uuid: (
      value.0, value.1, value.2, value.3,
      value.4, value.5, value.6, value.7,
      value.8, value.9, value.10, value.11,
      value.12, value.13,
      value.14 ^ 0x80,
      value.15 ^ UInt8(truncatingIfNeeded: position + 1)
    )
  )
}

nonisolated func testGamePeriods(
  gameID: Game.ID,
  count: Int = 4,
  durationSeconds: Int = 900,
  breakDurationSeconds: Int = 0,
  breakDurations: [Int]? = nil
) -> [GamePeriod] {
  (0..<count).map { position in
    GamePeriod(
      id: testGamePeriodID(gameID: gameID, position: position),
      gameID: gameID,
      position: position,
      durationSeconds: durationSeconds,
      breakAfterDurationSeconds: position < count - 1
        ? breakDurations.flatMap { durations in
          durations.indices.contains(position) ? durations[position] : nil
        } ?? breakDurationSeconds
        : nil
    )
  }
}
