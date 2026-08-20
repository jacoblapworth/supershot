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

nonisolated enum GamePhase: Equatable, Hashable, Sendable {
  case quarter(number: Int, durationSeconds: Int)
  case breakTime(afterQuarter: Int, durationSeconds: Int)

  var durationSeconds: Int {
    switch self {
    case let .quarter(_, durationSeconds), let .breakTime(_, durationSeconds):
      max(durationSeconds, 0)
    }
  }

  var quarterNumber: Int {
    switch self {
    case let .quarter(number, _):
      number
    case let .breakTime(afterQuarter, _):
      afterQuarter
    }
  }

  var isBreak: Bool {
    if case .breakTime = self { true } else { false }
  }

  var isQuarter: Bool { !isBreak }
}

nonisolated struct GameCountdown: Equatable, Hashable, Sendable {
  var elapsedSeconds = 0
  var endsAt: Date?

  var isRunning: Bool { endsAt != nil }
}

@Table
nonisolated struct Game: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  var startedAt: Date
  var endedAt: Date?
  var teamAID: Team.ID
  var teamABibColorHex = TeamColorPalette.blue
  var teamBID: Team.ID
  var teamBBibColorHex = TeamColorPalette.red
  var centrePassTeamID: Team.ID?
  var periodDurationSeconds: Int
  var firstBreakDurationSeconds = 0
  var halfTimeDurationSeconds = 0
  var secondBreakDurationSeconds = 0
  var isAwaitingCentrePassConfirmation = false
  var currentPhaseIndex = 0
  var elapsedSeconds = 0
  var timerEndsAt: Date? = nil

  var phases: [GamePhase] {
    [
      .quarter(number: 1, durationSeconds: periodDurationSeconds),
      .breakTime(afterQuarter: 1, durationSeconds: firstBreakDurationSeconds),
      .quarter(number: 2, durationSeconds: periodDurationSeconds),
      .breakTime(afterQuarter: 2, durationSeconds: halfTimeDurationSeconds),
      .quarter(number: 3, durationSeconds: periodDurationSeconds),
      .breakTime(afterQuarter: 3, durationSeconds: secondBreakDurationSeconds),
      .quarter(number: 4, durationSeconds: periodDurationSeconds),
    ]
  }

  var currentPhase: GamePhase {
    phases[Swift.min(Swift.max(currentPhaseIndex, 0), phases.count - 1)]
  }

  var countdown: GameCountdown {
    get { GameCountdown(elapsedSeconds: elapsedSeconds, endsAt: timerEndsAt) }
    set {
      elapsedSeconds = newValue.elapsedSeconds
      timerEndsAt = newValue.endsAt
    }
  }
}

@Table
nonisolated struct Team: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  var colorHex: String
  var name: String
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
  var quarterNumber: Int
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
  nonisolated mutating func bootstrapDatabase() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.add(function: $uuid)
    }

    let database = try SQLiteData.defaultDatabase(configuration: configuration)
    logger.debug(
      """
      DEBUG: ℹ️ App database:
      open "\(database.path)"
      """
    )
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
          "startedAt" TEXT NOT NULL,
          "endedAt" TEXT,
          "teamAID" TEXT NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE,
          "teamABibColorHex" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '#007AFF',
          "teamBID" TEXT NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE,
          "teamBBibColorHex" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '#FF3B30',
          "centrePassTeamID" TEXT REFERENCES "teams"("id") ON DELETE CASCADE,
          "periodDurationSeconds" INTEGER NOT NULL,
          "firstBreakDurationSeconds" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "halfTimeDurationSeconds" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "secondBreakDurationSeconds" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "isAwaitingCentrePassConfirmation" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "currentPhaseIndex" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "elapsedSeconds" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "timerEndsAt" TEXT
        ) STRICT
        """)
      .execute(db)

      try #sql("""
        CREATE TABLE "goals"(
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "gameID" TEXT NOT NULL REFERENCES "games"("id") ON DELETE CASCADE,
          "centrePassTeamID" TEXT REFERENCES "teams"("id") ON DELETE SET NULL,
          "teamID" TEXT NOT NULL REFERENCES "teams"("id") ON DELETE CASCADE,
          "quarterNumber" INTEGER NOT NULL,
          "elapsedSeconds" INTEGER NOT NULL,
          "points" INTEGER NOT NULL,
          "createdAt" TEXT NOT NULL
        ) STRICT
        """)
      .execute(db)
      try #sql(
        """
        CREATE INDEX "idx_games_teamAID"
        ON "games"("teamAID")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX "idx_games_teamBID"
        ON "games"("teamBID")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX "idx_goals_gameID"
        ON "goals"("gameID")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX "idx_goals_gameID_createdAt"
        ON "goals"("gameID", "createdAt")
        """
      )
      .execute(db)
    }

    try migrator.migrate(database)
    defaultDatabase = database
  }
}

nonisolated private let logger = Logger(subsystem: "Supershot", category: "Database")
