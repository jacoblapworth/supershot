import CustomDump
@testable import Database
import Dependencies
import Foundation
import GameCore
import SQLiteData
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  struct TeamFavoritesTests {
    @Test
    func favoritesOrderAndCleanupWithoutChangingGames() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let teams = [
        Team(id: UUID(71), name: "Aces"),
        Team(id: UUID(72), name: "Ravens"),
        Team(id: UUID(73), name: "Swifts"),
        Team(id: UUID(74), name: "Ravens"),
      ]
      let game = Game(id: UUID(75), startedAt: nil, teamAID: teams[0].id, teamBID: teams[1].id)
      try await database.write { db in
        try Team.insert { teams }.execute(db)
        _ = try GameSetupDraft(game: game, periods: testGamePeriods(gameID: game.id)).save(db)
      }
      let originalGames = try await database.read { db in try GamesRequest().fetch(db) }
      #expect(try await database.read { db in try TeamFavorite.fetchCount(db) } == 0)
      try await database.write { db in
        for team in teams.dropFirst() {
          try TeamFavorite.setFavorite(true, teamID: team.id, in: db)
          try TeamFavorite.setFavorite(true, teamID: team.id, in: db)
        }
        _ = try GameSetupDraft(game: game, periods: testGamePeriods(gameID: game.id)).save(db)
      }
      let favoriteList = try await database.read { db in try TeamsRequest().fetch(db) }
      #expect(favoriteList.teams.map(\.id) == [teams[1].id, teams[3].id, teams[2].id, teams[0].id])
      #expect(favoriteList.teams.map(\.isFavorite) == [true, true, true, false])
      let gamesAfter = try await database.read { db in try GamesRequest().fetch(db) }
      let teamsAfter = try await database.read { db in try Team.order { $0.id }.fetchAll(db) }
      expectNoDifference(gamesAfter, originalGames)
      expectNoDifference(teamsAfter, teams)
      try await database.write { db in
        try Team.find(teams[2].id).update { $0.name = "Aardvarks" }.execute(db)
      }
      #expect(try await database.read { db in try SavedTeamsRequest().fetch(db).teams.first?.id } == teams[2].id)
      try await database.write { db in
        try TeamFavorite.setFavorite(false, teamID: teams[2].id, in: db)
        try Team.find(teams[1].id).delete().execute(db)
      }
      #expect(try await database.read { db in try TeamFavorite.fetchAll(db).map(\.id) } == [teams[3].id])
    }
  }
}
