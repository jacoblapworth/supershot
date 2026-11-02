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
  struct TeamLogoQueriesTests {
    @Test(arguments: [0, 1, 2])
    func currentLogoUpdatesAcrossTeamAndGameQueriesWithoutChangingBibColours(status: Int) async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let teamID = UUID(81)
      let gameID = UUID(83)
      let date = Date(timeIntervalSince1970: 1000)
      try await database.write { db in
        try Team.insert {
          Team(id: teamID, name: "Ravens", logoData: Data([1]))
          Team(id: UUID(82), name: "Owls")
        }.execute(db)
        try Game.insert {
          Game(
            id: gameID,
            startedAt: status == 0 ? nil : date,
            endedAt: status == 2 ? date.addingTimeInterval(100) : nil,
            teamAID: teamID,
            teamABibColorHex: "#123456",
            teamBID: UUID(82),
            teamBBibColorHex: "#654321"
          )
        }.execute(db)
        try GamePeriod.insert { testGamePeriods(gameID: gameID) }.execute(db)
      }
      let before = try await database.read { db in try GamesRequest().fetch(db) }
      expectNoDifference(before.games.first?.teamALogoData, Data([1]))
      try await database.write { db in
        try Team.find(teamID).update {
          $0.logoData = #bind(Data([2]))
          $0.colorHex = "#FF0000"
        }.execute(db)
      }
      let after = try await database.read { db in
        try (GamesRequest().fetch(db), TeamsRequest().fetch(db), TeamDetailRequest(teamID: teamID).fetch(db))
      }
      expectNoDifference(after.0.games.first?.teamALogoData, Data([2]))
      expectNoDifference(after.1.teams.first { $0.id == teamID }?.logoData, Data([2]))
      expectNoDifference(after.2.team?.logoData, Data([2]))
      expectNoDifference(after.2.games.first?.teamALogoData, Data([2]))
      expectNoDifference(after.0.games.first?.teamABibColorHex, "#123456")
      expectNoDifference(after.0.games.first?.teamBBibColorHex, "#654321")
      try await database.write { db in
        try Team.find(teamID).update { $0.logoData = #bind(Data?.none) }.execute(db)
      }
      let removed = try await database.read { db in try GamesRequest().fetch(db) }
      #expect(removed.games.first?.teamALogoData == nil)
      let team = try await database.read { db in try Team.find(teamID).fetchOne(db) }
      expectNoDifference(team?.colorHex, "#FF0000")
    }
  }
}
