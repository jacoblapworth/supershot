//
//  Schema.swift
//  Netscore
//
//  Created by J on 01/08/2026.
//

import Foundation
import OSLog
import SQLiteData
import SwiftUI

@Table
nonisolated struct Game: Hashable, Identifiable {
  var id: UUID
  var date: Date
  
  var teamAID: Team.ID
  var teamBID: Team.ID
  
//  var periods: [Period]
//  var goals: [Goal]
}

@Table
struct Team: Identifiable {
  var id: UUID
  var name: String
}

@Table
struct Goal: Identifiable {
  var id: UUID
  var gameID: Game.ID
  var teamID: Team.ID
  var points: Int = 1
  var date: Date
}

extension DependencyValues {
  mutating func bootstrapDatabase() throws {
    let database = try SQLiteData.defaultDatabase()
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
        CREATE TABLE "games"(
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "title" TEXT NOT NULL,
          "teamAID" TEXT NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE,
          "teamBID" TEXT NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE
        ) STRICT
        """)
      .execute(db)
      
      try #sql("""
        CREATE TABLE "teams"(
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "name" TEXT NOT NULL
        ) STRICT
        """)
      .execute(db)
      
      try #sql("""
        CREATE TABLE "goals"(
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "gameID" TEXT NOT NULL REFERENCES "games"("id") ON DELETE CASCADE,
          "teamID" TEXT NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE,
          "date" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT CURRENT_TIMESTAMP,
          "points" INTEGER NOT NULL DEFAULT (1)
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
    }

    try migrator.migrate(database)
    defaultDatabase = database
  }
}

private let logger = Logger(subsystem: "Netscore", category: "Database")
