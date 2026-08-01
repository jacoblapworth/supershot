//
//  Schema.swift
//  Netscore
//
//  Created by J on 01/08/2026.
//

import Foundation
import Dependencies
import OSLog
import SQLiteData

@Table
nonisolated struct Game: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  var startedAt: Date
  var endedAt: Date?
  var teamAID: Team.ID
  var teamBID: Team.ID
  var periodDurationSeconds: Int
}

@Table
nonisolated struct Team: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  var name: String
}

@Table
nonisolated struct Goal: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  var gameID: Game.ID
  var teamID: Team.ID
  var period: Int
  var elapsedSeconds: Int
  var points: Int
  var createdAt: Date
}

@DatabaseFunction
nonisolated func uuid() -> UUID {
  @Dependency(\.uuid) var uuid
  return uuid()
}

extension DependencyValues {
  mutating func bootstrapDatabase() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.add(function: $uuid)
    }

    let database = try SQLiteData.defaultDatabase(configuration: configuration)
    logger.debug(
      """
      App database:
      open "\(database.path)"
      """
    )
    var migrator = DatabaseMigrator()

#if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
#endif

    migrator.registerMigration("Create initial tables") { db in
      try #sql("""
        CREATE TABLE "teams"(
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL
        ) STRICT
        """)
      .execute(db)

      try #sql("""
        CREATE TABLE "games"(
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "startedAt" TEXT NOT NULL,
          "endedAt" TEXT,
          "teamAID" TEXT NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE,
          "teamBID" TEXT NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE,
          "periodDurationSeconds" INTEGER NOT NULL
        ) STRICT
        """)
      .execute(db)

      try #sql("""
        CREATE TABLE "goals"(
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "gameID" TEXT NOT NULL REFERENCES "games"("id") ON DELETE CASCADE,
          "teamID" TEXT NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE,
          "period" INTEGER NOT NULL,
          "elapsedSeconds" INTEGER NOT NULL,
          "points" INTEGER NOT NULL,
          "createdAt" TEXT NOT NULL
        ) STRICT
        """)
      .execute(db)
    }

    migrator.registerMigration("Create foreign key indexes") { db in
      try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_games_teamAID"
        ON "games"("teamAID")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_games_teamBID"
        ON "games"("teamBID")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_goals_gameID"
        ON "goals"("gameID")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX IF NOT EXISTS "idx_goals_gameID_createdAt"
        ON "goals"("gameID", "createdAt")
        """
      )
      .execute(db)
    }

    try migrator.migrate(database)
    defaultDatabase = database
  }
}

private let logger = Logger(subsystem: "Netscore", category: "Database")
