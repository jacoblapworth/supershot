import Foundation
import GameCore
import SQLiteData

/// A complete, valid setup. Saving never changes a game that has already started.
package nonisolated struct GameSetupDraft: Equatable, Sendable {
  package var game: Game
  package var periods: [GamePeriod]
  package var teamsToCreate: [Team]

  package init(game: Game, periods: [GamePeriod], teamsToCreate: [Team] = []) {
    self.game = game
    self.periods = periods
    self.teamsToCreate = teamsToCreate
  }

  package enum SaveError: Error {
    case gameAlreadyStarted
    case gameUnavailable
    case invalidSetup
  }

  package func save(
    _ db: Database, startingAt: Date? = nil, requiresExistingGame: Bool = false
  ) throws -> GameSnapshot {
    guard game.teamAID != game.teamBID, GameTimeline(periods: periods) != nil,
          periods.allSatisfy({ $0.gameID == game.id })
    else { throw SaveError.invalidSetup }
    let selectedIDs: Set<Team.ID> = [game.teamAID, game.teamBID]
    guard Set(teamsToCreate.map(\.id)).count == teamsToCreate.count,
          teamsToCreate.allSatisfy({ selectedIDs.contains($0.id) && !$0.name.isEmpty })
    else { throw SaveError.invalidSetup }
    for team in teamsToCreate {
      if let existing = try Team.find(team.id).fetchOne(db) {
        guard existing == team else { throw SaveError.invalidSetup }
      } else {
        try Team.insert { team }.execute(db)
      }
    }
    var saved = game
    saved.startedAt = startingAt
    if let existing = try Game.find(game.id).fetchOne(db) {
      guard existing.isPlanned else { throw SaveError.gameAlreadyStarted }
      try Game.find(game.id).update {
        $0.startedAt = #bind(saved.startedAt)
        $0.scheduledAt = #bind(saved.scheduledAt)
        $0.court = #bind(saved.court)
        $0.division = #bind(saved.division)
        $0.teamAID = saved.teamAID
        $0.teamBID = saved.teamBID
        $0.teamABibColorHex = saved.teamABibColorHex
        $0.teamBBibColorHex = saved.teamBBibColorHex
        $0.centrePassTeamID = #bind(saved.centrePassTeamID)
        $0.latitude = #bind(saved.latitude)
        $0.longitude = #bind(saved.longitude)
        $0.pointOfInterestName = #bind(saved.pointOfInterestName)
        $0.breakStartPolicy = saved.breakStartPolicy
      }.execute(db)
      try GamePeriod.where { $0.gameID.eq(saved.id) }.delete().execute(db)
    } else {
      guard !requiresExistingGame else { throw SaveError.gameUnavailable }
      try Game.insert { saved }.execute(db)
    }
    try GamePeriod.insert { periods }.execute(db)
    return try GameSnapshot.fetch(db, gameID: saved.id)
  }
}
