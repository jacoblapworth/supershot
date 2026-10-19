import Foundation
import SQLiteData
import SharedModels

nonisolated public enum BreakStartPolicy: String, Codable, CaseIterable, Sendable, QueryBindable {
  case automatic
  case manual
}

@Table
nonisolated public struct Game: Equatable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public var startedAt: Date
  public var endedAt: Date?
  public var teamAID: Team.ID
  public var teamABibColorHex = "#007AFF"
  public var teamBID: Team.ID
  public var teamBBibColorHex = "#FF3B30"
  public var centrePassTeamID: Team.ID?
  public var swapSides = false
  public var latitude: Double?
  public var longitude: Double?
  public var pointOfInterestName: String?
  public var isAwaitingCentrePassConfirmation = false
  public var lateScoringPeriodNumber: Int?
  public var currentPhaseIndex = 0
  public var elapsedSeconds = 0
  public var timerEndsAt: Date? = nil
  public var breakStartPolicy = BreakStartPolicy.automatic

  public var countdown: GameCountdown {
    get { GameCountdown(elapsedSeconds: elapsedSeconds, endsAt: timerEndsAt) }
    set {
      elapsedSeconds = newValue.elapsedSeconds
      timerEndsAt = newValue.endsAt
    }
  }

  public init(
    id: UUID, startedAt: Date, endedAt: Date? = nil, teamAID: Team.ID,
    teamABibColorHex: String = "#007AFF", teamBID: Team.ID, teamBBibColorHex: String = "#FF3B30",
    centrePassTeamID: Team.ID? = nil, swapSides: Bool = false, latitude: Double? = nil,
    longitude: Double? = nil, pointOfInterestName: String? = nil,
    isAwaitingCentrePassConfirmation: Bool = false, lateScoringPeriodNumber: Int? = nil,
    currentPhaseIndex: Int = 0, elapsedSeconds: Int = 0, timerEndsAt: Date? = nil,
    breakStartPolicy: BreakStartPolicy = BreakStartPolicy.automatic
  ) {
    self.id = id
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.teamAID = teamAID
    self.teamABibColorHex = teamABibColorHex
    self.teamBID = teamBID
    self.teamBBibColorHex = teamBBibColorHex
    self.centrePassTeamID = centrePassTeamID
    self.swapSides = swapSides
    self.latitude = latitude
    self.longitude = longitude
    self.pointOfInterestName = pointOfInterestName
    self.isAwaitingCentrePassConfirmation = isAwaitingCentrePassConfirmation
    self.lateScoringPeriodNumber = lateScoringPeriodNumber
    self.currentPhaseIndex = currentPhaseIndex
    self.elapsedSeconds = elapsedSeconds
    self.timerEndsAt = timerEndsAt
    self.breakStartPolicy = breakStartPolicy
  }
}

extension Game {
  nonisolated public var progress: GameProgress {
    get { GameProgress(timing: timing, scoring: scoring) }
    set {
      timing = newValue.timing
      scoring = newValue.scoring
    }
  }
}

@Table
nonisolated public struct GamePeriod: Equatable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public var gameID: Game.ID
  public var position: Int
  public var durationSeconds: Int
  public var breakAfterDurationSeconds: Int?

  public init(
    id: UUID,
    gameID: Game.ID,
    position: Int,
    durationSeconds: Int,
    breakAfterDurationSeconds: Int? = nil
  ) {
    self.id = id
    self.gameID = gameID
    self.position = position
    self.durationSeconds = durationSeconds
    self.breakAfterDurationSeconds =
      breakAfterDurationSeconds == 0 ? nil : breakAfterDurationSeconds
  }

  /// User facing number presentation
  public var number: Int { position + 1 }
}

extension Game {
  nonisolated public var location: GameLocation? {
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
nonisolated public struct Team: Equatable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public var colorHex: String
  public var name: String

  public init(id: UUID, colorHex: String, name: String) {
    self.id = id
    self.colorHex = colorHex
    self.name = name
  }
}

extension Team {
  nonisolated public init(
    id: UUID,
    name: String,
    colorHex: String = "#007AFF"
  ) {
    self.id = id
    self.colorHex =
      HexColor.isValid(colorHex)
      ? colorHex.uppercased()
      : "#007AFF"
    self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

@Table
nonisolated public struct Goal: Equatable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public var gameID: Game.ID
  public var gamePeriodID: GamePeriod.ID
  public var centrePassTeamID: Team.ID? = nil
  public var teamID: Team.ID
  public var elapsedSeconds: Int
  public var isLate = false
  public var points: Int = 1
  public var createdAt: Date

  public init(
    id: UUID, gameID: Game.ID, gamePeriodID: GamePeriod.ID, centrePassTeamID: Team.ID? = nil,
    teamID: Team.ID, elapsedSeconds: Int, isLate: Bool = false, points: Int = 1, createdAt: Date
  ) {
    self.id = id
    self.gameID = gameID
    self.gamePeriodID = gamePeriodID
    self.centrePassTeamID = centrePassTeamID
    self.teamID = teamID
    self.elapsedSeconds = elapsedSeconds
    self.isLate = isLate
    self.points = points
    self.createdAt = createdAt
  }
}

extension Team.Draft: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id && lhs.name == rhs.name && lhs.colorHex == rhs.colorHex
  }
}
