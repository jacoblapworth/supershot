import CustomDump
import Dependencies
import Foundation
import GRDB
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct DatabaseMigrationTests {
    @Test
    func runningTimerMigrationLeavesExistingProgressPaused() throws {
      let database = try DatabaseQueue()
      try database.write { db in
        try db.execute(
          sql: """
            CREATE TABLE "games"(
              "id" TEXT PRIMARY KEY NOT NULL,
              "elapsedSeconds" INTEGER NOT NULL
            ) STRICT
            """
        )
        try db.execute(
          sql: "INSERT INTO \"games\" (\"id\", \"elapsedSeconds\") VALUES (?, ?)",
          arguments: [UUID(3).uuidString, 42]
        )

        try migrateAddRunningTimerEndDate(db)

        let row = try Row.fetchOne(
          db,
          sql: "SELECT \"elapsedSeconds\", \"timerEndsAt\" FROM \"games\""
        )
        expectNoDifference(row?["elapsedSeconds"] as Int?, 42)
        expectNoDifference(row?["timerEndsAt"] as String?, nil)
      }
    }

    @Test
    func perGameBibColorMigrationSnapshotsTeamColorsAndUsesFallbacks() throws {
      let database = try DatabaseQueue()
      try database.write { db in
        try db.execute(
          sql: """
            CREATE TABLE "teams"(
              "id" TEXT PRIMARY KEY NOT NULL,
              "colorHex" TEXT NOT NULL
            ) STRICT
            """
        )
        try db.execute(
          sql: """
            CREATE TABLE "games"(
              "id" TEXT PRIMARY KEY NOT NULL,
              "teamAID" TEXT NOT NULL,
              "teamBID" TEXT NOT NULL
            ) STRICT
            """
        )
        try db.execute(
          sql: "INSERT INTO \"teams\" (\"id\", \"colorHex\") VALUES (?, ?), (?, ?)",
          arguments: [
            UUID(1).uuidString, "#34C759",
            UUID(2).uuidString, "#FF9500",
          ]
        )
        try db.execute(
          sql: "INSERT INTO \"games\" (\"id\", \"teamAID\", \"teamBID\") VALUES (?, ?, ?), (?, ?, ?)",
          arguments: [
            UUID(3).uuidString, UUID(1).uuidString, UUID(2).uuidString,
            UUID(4).uuidString, UUID(5).uuidString, UUID(6).uuidString,
          ]
        )

        try migrateAddPerGameBibColors(db)

        let rows = try Row.fetchAll(
          db,
          sql: "SELECT \"teamABibColorHex\", \"teamBBibColorHex\" FROM \"games\" ORDER BY \"id\""
        )
        expectNoDifference(rows[0]["teamABibColorHex"] as String?, "#34C759")
        expectNoDifference(rows[0]["teamBBibColorHex"] as String?, "#FF9500")
        expectNoDifference(rows[1]["teamABibColorHex"] as String?, TeamColorPalette.blue)
        expectNoDifference(rows[1]["teamBBibColorHex"] as String?, TeamColorPalette.red)

        try db.execute(
          sql: "UPDATE \"teams\" SET \"colorHex\" = '#AF52DE'"
        )
        let unchangedRow = try Row.fetchOne(
          db,
          sql: "SELECT \"teamABibColorHex\", \"teamBBibColorHex\" FROM \"games\" WHERE \"id\" = ?",
          arguments: [UUID(3).uuidString]
        )
        expectNoDifference(unchangedRow?["teamABibColorHex"] as String?, "#34C759")
        expectNoDifference(unchangedRow?["teamBBibColorHex"] as String?, "#FF9500")
      }
    }
  }
}
