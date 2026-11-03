import Foundation
import GameCore
import SQLiteData

@Table
package nonisolated struct TeamFavorite: Equatable, Identifiable, Sendable {
  package let id: Team.ID

  package init(id: Team.ID) {
    self.id = id
  }

  package static func setFavorite(_ isFavorite: Bool, teamID: Team.ID, in db: Database) throws {
    guard try Team.find(teamID).fetchOne(db) != nil else {
      throw SaveError.teamUnavailable
    }
    if isFavorite {
      try upsert { Self(id: teamID) }.execute(db)
    } else {
      try find(teamID).delete().execute(db)
    }
  }

  package enum SaveError: Error {
    case teamUnavailable
  }
}

package nonisolated struct SavedTeamsRequest: FetchKeyRequest {
  package struct Value: Equatable, Sendable {
    package var teams: [Team] = []
    package var favoriteIDs: Set<Team.ID> = []
  }

  package func fetch(_ db: Database) throws -> Value {
    let favoriteIDs = try Set(TeamFavorite.fetchAll(db).map(\.id))
    let teams = try Team
      .leftJoin(TeamFavorite.all) { $0.id.eq($1.id) }
      .order { ($1.id.isNot(nil).desc(), $0.name, $0.id) }
      .select { teams, _ in teams }
      .fetchAll(db)
    return Value(teams: teams, favoriteIDs: favoriteIDs)
  }

  package init() {}
}
