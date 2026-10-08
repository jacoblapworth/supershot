import CryptoKit
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
  let bytes = Array(SHA256.hash(data: Data("\(gameID.uuidString):\(position)".utf8)))
  return UUID(uuid: (
    bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
    bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
  ))
}

nonisolated func testGamePeriods(
  gameID: Game.ID,
  count: Int = 4,
  durationSeconds: Int = 900,
  breakDurationSeconds: Int = 0,
  breakDurations: [Int]? = nil
) -> [GamePeriod] {
  return (0..<count).map { position in
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

nonisolated func testGamePeriodReference(
  number: Int,
  gameID: Game.ID = UUID(3)
) -> GamePeriodReference {
  GamePeriodReference(id: testGamePeriodID(gameID: gameID, position: number - 1), number: number)
}
