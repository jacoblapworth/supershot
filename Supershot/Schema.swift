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
  var centrePassTeamID: Team.ID?
  var periodDurationSeconds: Int
  var firstBreakDurationSeconds = 0
  var halfTimeDurationSeconds = 0
  var secondBreakDurationSeconds = 0
  var isInBreak = false
  var isAwaitingCentrePassConfirmation = false
  var currentPeriod = 1
  var elapsedSeconds = 0
  var hasTimerStartedCurrentPeriod = false
  var timerEndsAt: Date? = nil

  func breakDuration(after period: Int) -> Int {
    switch period {
    case 1:
      firstBreakDurationSeconds
    case 2:
      halfTimeDurationSeconds
    case 3:
      secondBreakDurationSeconds
    default:
      0
    }
  }
}

@Table
nonisolated struct Team: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  var colorHex: String
  var name: String
  var normalizedName: String
}

extension Team {
  nonisolated init(
    id: UUID,
    name: String,
    colorHex: String = TeamColorPalette.blue
  ) {
    self.id = id
    self.colorHex = TeamColorPalette.isValid(colorHex)
      ? colorHex.uppercased()
      : TeamColorPalette.blue
    self.name = Self.trimmedName(name)
    self.normalizedName = Self.normalizeName(name)
  }

  nonisolated static func normalizeName(_ name: String) -> String {
    trimmedName(name)
      .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .precomposedStringWithCanonicalMapping
  }

  nonisolated static func trimmedName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

@Table
nonisolated struct Goal: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  var gameID: Game.ID
  var centrePassTeamID: Team.ID? = nil
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

@DatabaseFunction
nonisolated func normalizedTeamName(_ name: String) -> String {
  Team.normalizeName(name)
}

extension DependencyValues {
  nonisolated mutating func bootstrapDatabase() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.add(function: $uuid)
      db.add(function: $normalizedTeamName)
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

    migrator.registerMigration("Add resumable game progress") { db in
      try #sql(
        """
        ALTER TABLE "games"
        ADD COLUMN "currentPeriod" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 1
        """
      )
      .execute(db)
      try #sql(
        """
        ALTER TABLE "games"
        ADD COLUMN "elapsedSeconds" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
        """
      )
      .execute(db)
      try #sql(
        """
        ALTER TABLE "games"
        ADD COLUMN "hasTimerStartedCurrentPeriod" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
        """
      )
      .execute(db)
    }

    migrator.registerMigration("Add centre pass tracking") { db in
      try #sql(
        """
        ALTER TABLE "games"
        ADD COLUMN "centrePassTeamID" TEXT REFERENCES "teams"("id") ON DELETE CASCADE
        """
      )
      .execute(db)

      try #sql(
        """
        UPDATE "games"
        SET "centrePassTeamID" = "teamAID"
        WHERE "centrePassTeamID" IS NULL
        """
      )
      .execute(db)
    }

    migrator.registerMigration("Add per-break game timing") { db in
      try #sql(
        """
        ALTER TABLE "games"
        ADD COLUMN "firstBreakDurationSeconds" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
        """
      )
      .execute(db)
      try #sql(
        """
        ALTER TABLE "games"
        ADD COLUMN "halfTimeDurationSeconds" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
        """
      )
      .execute(db)
      try #sql(
        """
        ALTER TABLE "games"
        ADD COLUMN "secondBreakDurationSeconds" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
        """
      )
      .execute(db)
      try #sql(
        """
        ALTER TABLE "games"
        ADD COLUMN "isInBreak" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
        """
      )
      .execute(db)
    }

    migrator.registerMigration("Add reusable team profiles") { db in
      try #sql(
        """
        ALTER TABLE "teams"
        ADD COLUMN "colorHex" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '#007AFF'
        """
      )
      .execute(db)
      try #sql(
        """
        ALTER TABLE "teams"
        ADD COLUMN "normalizedName" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
        """
      )
      .execute(db)

      let teams = try Team.fetchAll(db)
      let groups = Dictionary(grouping: teams) {
        Team.normalizeName($0.name)
      }

      for (normalizedName, group) in groups {
        let sorted = group.sorted { $0.id.uuidString < $1.id.uuidString }
        guard let survivor = sorted.first else { continue }

        for duplicate in sorted.dropFirst() {
          try Game
            .where { $0.teamAID.eq(duplicate.id) }
            .update { $0.teamAID = #bind(survivor.id) }
            .execute(db)
          try Game
            .where { $0.teamBID.eq(duplicate.id) }
            .update { $0.teamBID = #bind(survivor.id) }
            .execute(db)
          try Game
            .where { $0.centrePassTeamID.eq(duplicate.id) }
            .update { $0.centrePassTeamID = #bind(survivor.id) }
            .execute(db)
          try Goal
            .where { $0.teamID.eq(duplicate.id) }
            .update { $0.teamID = #bind(survivor.id) }
            .execute(db)
          try Team.find(duplicate.id).delete().execute(db)
        }

        let trimmedName = Team.trimmedName(survivor.name)
        try Team.find(survivor.id).update {
          $0.name = #bind(trimmedName)
          $0.normalizedName = #bind(normalizedName)
        }
        .execute(db)
      }

      let remainingTeams = try Team
        .order { ($0.normalizedName, $0.id) }
        .fetchAll(db)
      for (index, team) in remainingTeams.enumerated() {
        let colorHex = TeamColorPalette.options[index % TeamColorPalette.options.count].hex
        try Team.find(team.id).update {
          $0.colorHex = #bind(colorHex)
        }
        .execute(db)
      }

      try #sql(
        """
        CREATE UNIQUE INDEX "idx_teams_normalizedName"
        ON "teams"("normalizedName")
        """
      )
      .execute(db)
    }

    migrator.registerMigration("Persist centre pass confirmation") { db in
      try #sql(
        """
        ALTER TABLE "games"
        ADD COLUMN "isAwaitingCentrePassConfirmation" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
        """
      )
      .execute(db)
    }

    migrator.registerMigration("Add running timer end date") { db in
      try migrateAddRunningTimerEndDate(db)
    }

    migrator.registerMigration("Record goal centre pass team") { db in
      try #sql(
        """
        ALTER TABLE "goals"
        ADD COLUMN "centrePassTeamID" TEXT REFERENCES "teams"("id") ON DELETE SET NULL
        """
      )
      .execute(db)
    }

    try migrator.migrate(database)
    defaultDatabase = database
  }
}

nonisolated func migrateAddRunningTimerEndDate(_ db: Database) throws {
  try #sql(
    """
    ALTER TABLE "games"
    ADD COLUMN "timerEndsAt" TEXT
    """
  )
  .execute(db)
}

nonisolated private let logger = Logger(subsystem: "Supershot", category: "Database")
