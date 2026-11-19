//
//  TeamEntity.swift
//  Supershot
//
//  Created by J on 19/11/2026.
//


import AppIntents
import Dependencies
import Foundation
import GameCore
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
      try Team
        .where { $0.id.in(identifiers) }
        .fetchAll(db)
        .map(TeamEntity.init)
    }
  }
  
  func entities(matching string: String) async throws -> [TeamEntity] {
    try await database.read { db in
      try Team
        .where { $0.name.like("%\(string)%") }
        .order(by: \.name)
        .limit(50)
        .fetchAll(db)
        .map(TeamEntity.init)
    }
  }
  
  func suggestedEntities() async throws -> [TeamEntity] {
    try await database.read { db in
      try Team
        .order(by: \.name)
        .limit(50)
        .fetchAll(db)
        .map(TeamEntity.init)
    }
  }
}
