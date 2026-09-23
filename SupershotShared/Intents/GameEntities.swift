import AppIntents
import Dependencies
import Foundation
import SQLiteData

struct TeamEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Team"
  static let defaultQuery = TeamEntityQuery()

  let id: UUID
  @Property(title: "Name") var name: String
  @Property(title: "Color") var colorHex: String

  init(team: Team) {
    id = team.id
    name = team.name
    colorHex = team.colorHex
  }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}

nonisolated struct TeamEntityQuery: EntityStringQuery {
  @Dependencies.Dependency(\.defaultDatabase) private var database

  func entities(for identifiers: [UUID]) async throws -> [TeamEntity] {
    try await database.read { db in
      try Team.where { $0.id.in(identifiers) }.fetchAll(db).map(TeamEntity.init)
    }
  }

  func entities(matching string: String) async throws -> [TeamEntity] {
    try await database.read { db in
      try Team.where { $0.name.like("%\(string)%") }.order(by: \.name)
        .limit(50).fetchAll(db).map(TeamEntity.init)
    }
  }

  func suggestedEntities() async throws -> [TeamEntity] {
    try await database.read { db in
      try Team.order(by: \.name).limit(50).fetchAll(db).map(TeamEntity.init)
    }
  }
}

struct GameEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Game"
  static let defaultQuery = GameEntityQuery()

  let id: UUID
  @Property(title: "Team A") var teamA: TeamEntity
  @Property(title: "Team B") var teamB: TeamEntity
  @Property(title: "Started At") var startedAt: Date
  @Property(title: "Completed") var isCompleted: Bool

  init(game: Game, teamA: Team, teamB: Team) {
    id = game.id
    self.teamA = TeamEntity(team: teamA)
    self.teamB = TeamEntity(team: teamB)
    startedAt = game.startedAt
    isCompleted = game.endedAt != nil
  }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(teamA.name) vs \(teamB.name)",
      subtitle: "\(startedAt.formatted(date: .abbreviated, time: .shortened))"
    )
  }
}

nonisolated struct GameEntityQuery: EntityStringQuery {
  @Dependencies.Dependency(\.defaultDatabase) private var database

  func entities(for identifiers: [UUID]) async throws -> [GameEntity] {
    try await database.read { db in
      try Self.entities(Game.where { $0.id.in(identifiers) }.fetchAll(db), in: db)
    }
  }

  func entities(matching string: String) async throws -> [GameEntity] {
    try await database.read { db in
      let teamIDs = try Team.where { $0.name.like("%\(string)%") }.fetchAll(db).map(\.id)
      let games = try Game.where {
        $0.teamAID.in(teamIDs) || $0.teamBID.in(teamIDs)
      }.order { $0.startedAt.desc() }.limit(50).fetchAll(db)
      return try Self.entities(games, in: db)
    }
  }

  func suggestedEntities() async throws -> [GameEntity] {
    try await database.read { db in
      try Self.entities(Game.order { $0.startedAt.desc() }.limit(20).fetchAll(db), in: db)
    }
  }

  private static func entities(_ games: [Game], in db: Database) throws -> [GameEntity] {
    let teamIDs = Set(games.flatMap { [$0.teamAID, $0.teamBID] })
    let teams = try Team.where { $0.id.in(teamIDs) }.fetchAll(db)
    let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
    return games.compactMap { game in
      guard let teamA = teamsByID[game.teamAID], let teamB = teamsByID[game.teamBID]
      else { return nil }
      return GameEntity(game: game, teamA: teamA, teamB: teamB)
    }
  }
}
