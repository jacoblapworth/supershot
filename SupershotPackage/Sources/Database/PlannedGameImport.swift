import Foundation
import GameCore
import SQLiteData

/// Stable draft IDs make retrying the same import idempotent. The savepoint also
/// protects callers that are already inside a larger database transaction.
package nonisolated struct PlannedGameImport: Sendable {
  package var drafts: [GameSetupDraft]
  package var matchedTeams: [Team]

  package init(drafts: [GameSetupDraft], matchedTeams: [Team]) {
    self.drafts = drafts
    self.matchedTeams = matchedTeams
  }

  package enum ImportError: Error {
    case invalidBatch
    case staleTeam
    case conflictingRetry
  }

  package func save(_ db: Database) throws -> [GameSnapshot] {
    guard !drafts.isEmpty, Set(drafts.map(\.game.id)).count == drafts.count,
          drafts.allSatisfy({ $0.game.scheduledAt != nil && $0.game.isPlanned })
    else { throw ImportError.invalidBatch }
    var snapshots: [GameSnapshot] = []
    try db.inSavepoint {
      for team in matchedTeams {
        guard let current = try Team.find(team.id).fetchOne(db), current.name == team.name
        else { throw ImportError.staleTeam }
      }
      var fixtures: [GameFixtureIdentity: Game.ID] = [:]
      for game in try Game.fetchAll(db) {
        if let identity = GameFixtureIdentity(game: game) {
          fixtures[identity] = game.id
        }
      }
      for draft in drafts {
        if let existing = try Game.find(draft.game.id).fetchOne(db) {
          // Never overwrite a changed or started game on a retry.
          guard existing == draft.game,
                try GamePeriod.where({ $0.gameID.eq(existing.id) }).order(by: \.position).fetchAll(db) == draft.periods
          else { throw ImportError.conflictingRetry }
          try snapshots.append(GameSnapshot.fetch(db, gameID: existing.id))
        } else if let identity = GameFixtureIdentity(game: draft.game), let id = fixtures[identity] {
          // Recheck inside the transaction: another import may have saved this
          // fixture since preview, or an earlier row may repeat it in this batch.
          try snapshots.append(GameSnapshot.fetch(db, gameID: id))
        } else {
          let snapshot = try draft.save(db)
          snapshots.append(snapshot)
          if let identity = GameFixtureIdentity(game: snapshot.game) {
            fixtures[identity] = snapshot.game.id
          }
        }
      }
      return .commit
    }
    return snapshots
  }
}
