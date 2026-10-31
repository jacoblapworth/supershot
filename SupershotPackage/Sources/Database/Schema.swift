import Dependencies
import Foundation
import GameCore
import OSLog
import SharedModels
import SQLiteData

public extension DependencyValues {
  nonisolated mutating func bootstrapDatabase() throws {
    let database = try SQLiteData.defaultDatabase()
    logger.debug("""
    DEBUG: ℹ️ App database:
    open "\(database.path)"
    """)
    var migrator = DatabaseMigrator()

    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("Create schema") { db in
      try #sql("""
      CREATE TABLE "teams"(
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "colorHex" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '#007AFF',
        "name" TEXT NOT NULL
      ) STRICT
      """)
      .execute(db)

      try #sql("""
      CREATE TABLE "games"(
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "startedAt" TEXT,
        "createdAt" TEXT NOT NULL,
        "scheduledAt" TEXT,
        "court" TEXT,
        "division" TEXT,
        "endedAt" TEXT,
        "teamAID" TEXT NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE,
        "teamABibColorHex" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '#007AFF',
        "teamBID" TEXT NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE,
        "teamBBibColorHex" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '#FF3B30',
        "centrePassTeamID" TEXT REFERENCES "teams"("id") ON DELETE CASCADE,
        "swapSides" INTEGER NOT NULL DEFAULT 0
          CHECK ("swapSides" IN (0, 1)),
        "latitude" REAL,
        "longitude" REAL,
        "pointOfInterestName" TEXT,
        "isAwaitingCentrePassConfirmation" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "lateScoringPeriodNumber" INTEGER CHECK ("lateScoringPeriodNumber" > 0),
        "currentPhaseIndex" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "elapsedSeconds" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
        "timerEndsAt" TEXT,
        "breakStartPolicy" TEXT NOT NULL DEFAULT 'automatic'
          CHECK ("breakStartPolicy" IN ('automatic', 'manual')),
        CHECK ("teamAID" != "teamBID"),
        CHECK ("endedAt" IS NULL OR "startedAt" IS NOT NULL),
        CHECK ("startedAt" IS NOT NULL OR "timerEndsAt" IS NULL),
        CHECK ("startedAt" IS NOT NULL OR "currentPhaseIndex" = 0)
      ) STRICT
      """)
      .execute(db)

      try #sql("""
      CREATE TABLE "gamePeriods"(
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "gameID" TEXT NOT NULL REFERENCES "games"("id") ON DELETE CASCADE,
        "position" INTEGER NOT NULL CHECK ("position" >= 0),
        "durationSeconds" INTEGER NOT NULL CHECK ("durationSeconds" > 0),
        "breakAfterDurationSeconds" INTEGER CHECK (
          "breakAfterDurationSeconds" > 0
        ),
        UNIQUE("gameID", "position"),
        UNIQUE("id", "gameID")
      ) STRICT
      """)
      .execute(db)

      try #sql("""
      CREATE TABLE "goals"(
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "gameID" TEXT NOT NULL,
        "gamePeriodID" TEXT NOT NULL,
        "centrePassTeamID" TEXT REFERENCES "teams"("id") ON DELETE SET NULL,
        "teamID" TEXT NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE,
        "elapsedSeconds" INTEGER NOT NULL,
        "isLate" INTEGER NOT NULL DEFAULT 0,
        "points" INTEGER NOT NULL,
        "createdAt" TEXT NOT NULL,
        FOREIGN KEY("gamePeriodID", "gameID")
          REFERENCES "gamePeriods"("id", "gameID") ON DELETE CASCADE
      ) STRICT
      """)
      .execute(db)
      try #sql("""
      CREATE INDEX "idx_games_teamAID"
      ON "games"("teamAID")
      """)
      .execute(db)
      try #sql("""
      CREATE INDEX "idx_games_teamBID"
      ON "games"("teamBID")
      """)
      .execute(db)
      try #sql("""
      CREATE INDEX "idx_gamePeriods_gameID_position"
      ON "gamePeriods"("gameID", "position")
      """)
      .execute(db)
      try #sql("""
      CREATE INDEX "idx_goals_gameID"
      ON "goals"("gameID")
      """)
      .execute(db)
      try #sql("""
      CREATE INDEX "idx_goals_gameID_createdAt"
      ON "goals"("gameID", "createdAt")
      """)
      .execute(db)
    }

    try migrator.migrate(database)
    defaultDatabase = database
  }
}

private nonisolated let logger = Logger(subsystem: "Supershot", category: "Database")
