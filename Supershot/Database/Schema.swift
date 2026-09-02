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
import CasePaths

/// Phase of a game
nonisolated enum GamePhase: Equatable, Hashable, Sendable {
  case period(number: Int, durationSeconds: Int)
  case breakTime(afterPeriod: Int, durationSeconds: Int)
  
  var durationSeconds: Int {
    switch self {
    case let .period(_, durationSeconds), let .breakTime(_, durationSeconds):
      max(durationSeconds, 0)
    }
  }
  
  var periodNumber: Int {
    switch self {
    case let .period(number, _):
      number
    case let .breakTime(afterQuarter, _):
      afterQuarter
    }
  }
  
  var isBreak: Bool {
    switch self {
    case .period: false
    case .breakTime: true
    }
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
  var latitude: Double?
  var longitude: Double?
  var pointOfInterestName: String?
  var isAwaitingCentrePassConfirmation = false
  var currentPhaseIndex = 0
  var elapsedSeconds = 0
  var timerEndsAt: Date? = nil
  
  var countdown: GameCountdown {
    get { GameCountdown(elapsedSeconds: elapsedSeconds, endsAt: timerEndsAt) }
    set {
      elapsedSeconds = newValue.elapsedSeconds
      timerEndsAt = newValue.endsAt
    }
  }
}

//@Table
//struct Phase {
//  let id: UUID
//  var kind: Kind
//  var duration: Int
//  
//  @Selection
//  enum Kind {
//    case period
//    case rest
//  }
//}

@Table
nonisolated struct GamePeriod: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  var gameID: Game.ID
  var position: Int
  var durationSeconds: Int
  var breakAfterDurationSeconds: Int?

  /// User facing number presentation
  var number: Int { position + 1 }
}

nonisolated func gamePhases(for periods: [GamePeriod]) -> [GamePhase] {
  periods
    .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
    .flatMap { period in
      var phases = [
        GamePhase.period(
          number: period.number,
          durationSeconds: period.durationSeconds
        )
      ]
      if let breakDurationSeconds = period.breakAfterDurationSeconds {
        phases.append(
          .breakTime(
            afterPeriod: period.number,
            durationSeconds: breakDurationSeconds
          )
        )
      }
      return phases
    }
}

extension Game {
  nonisolated var location: GameLocation? {
    get {
      guard let latitude, let longitude else { return nil }
      return GameLocation(
        latitude: latitude,
        longitude: longitude,
        pointOfInterestName: pointOfInterestName
      )
    }
    set {
      latitude = newValue?.latitude
      longitude = newValue?.longitude
      pointOfInterestName = newValue?.pointOfInterestName
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
  var gamePeriodID: GamePeriod.ID
  var centrePassTeamID: Team.ID? = nil
  var teamID: Team.ID
  var elapsedSeconds: Int
  var points: Int = 1
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
          "latitude" REAL,
          "longitude" REAL,
          "pointOfInterestName" TEXT,
          "isAwaitingCentrePassConfirmation" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "currentPhaseIndex" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "elapsedSeconds" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
          "timerEndsAt" TEXT
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
            "breakAfterDurationSeconds" >= 0
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
          "points" INTEGER NOT NULL,
          "createdAt" TEXT NOT NULL,
          FOREIGN KEY("gamePeriodID", "gameID")
            REFERENCES "gamePeriods"("id", "gameID") ON DELETE CASCADE
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
        CREATE INDEX "idx_gamePeriods_gameID_position"
        ON "gamePeriods"("gameID", "position")
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
