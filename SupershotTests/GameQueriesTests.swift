import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct GameQueriesTests {
    @Test
    func gameListIsNewestFirstWithScoresAndStatuses() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      let olderDate = Date(timeIntervalSince1970: 1_000)
      let newerDate = Date(timeIntervalSince1970: 2_000)
      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
          Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
          Team(id: UUID(-3), name: "Foxes", colorHex: "#34C759")
          Team(id: UUID(-4), name: "Owls", colorHex: "#FF9500")
          Game(
            id: UUID(-1),
            startedAt: newerDate,
            endedAt: nil,
            teamAID: UUID(-1),
            teamBID: UUID(-2),
            periodDurationSeconds: 900,
            firstBreakDurationSeconds: 240,
            halfTimeDurationSeconds: 600,
            secondBreakDurationSeconds: 240
          )
          Game(
            id: UUID(-2),
            startedAt: olderDate,
            endedAt: Date(timeIntervalSince1970: 1_500),
            teamAID: UUID(-3),
            teamABibColorHex: "#34C759",
            teamBID: UUID(-4),
            teamBBibColorHex: "#FF9500",
            periodDurationSeconds: 900
          )
          Goal(
            id: UUID(-1),
            gameID: UUID(-1),
            teamID: UUID(-1),
            period: 1,
            elapsedSeconds: 10,
            points: 2,
            createdAt: newerDate
          )
          Goal(
            id: UUID(-2),
            gameID: UUID(-2),
            teamID: UUID(-4),
            period: 1,
            elapsedSeconds: 20,
            points: 1,
            createdAt: olderDate
          )
        }
      }

      let value = try await database.read { db in
        try GamesRequest().fetch(db)
      }

      expectNoDifference(
        value.games,
        [
          GameListItem(
            endedAt: nil,
            firstBreakDurationSeconds: 240,
            halfTimeDurationSeconds: 600,
            id: UUID(-1),
            periodDurationSeconds: 900,
            secondBreakDurationSeconds: 240,
            startedAt: newerDate,
            teamABibColorHex: TeamColorPalette.blue,
            teamAName: "Ravens",
            teamAScore: 2,
            teamBBibColorHex: TeamColorPalette.red,
            teamBName: "Swifts",
            teamBScore: 0
          ),
          GameListItem(
            endedAt: Date(timeIntervalSince1970: 1_500),
            id: UUID(-2),
            startedAt: olderDate,
            teamABibColorHex: "#34C759",
            teamAName: "Foxes",
            teamAScore: 0,
            teamBBibColorHex: "#FF9500",
            teamBName: "Owls",
            teamBScore: 1
          ),
        ]
      )
    }

    @Test
    func gameHistoryKeepsBibColorsAfterTeamProfileColorsChange() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      let startedAt = Date(timeIntervalSince1970: 1_000)
      let updatedRavensColorHex = "#34C759"
      let updatedSwiftsColorHex = "#FF2D55"
      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
          Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
          Game(
            id: UUID(-1),
            startedAt: startedAt,
            endedAt: Date(timeIntervalSince1970: 2_000),
            teamAID: UUID(-1),
            teamABibColorHex: "#AF52DE",
            teamBID: UUID(-2),
            teamBBibColorHex: "#FF9500",
            periodDurationSeconds: 900
          )
          Game(
            id: UUID(-2),
            startedAt: Date(timeIntervalSince1970: 3_000),
            endedAt: nil,
            teamAID: UUID(-1),
            teamABibColorHex: "#30B0C7",
            teamBID: UUID(-2),
            teamBBibColorHex: "#FF2D55",
            periodDurationSeconds: 900
          )
          Goal(
            id: UUID(-1),
            gameID: UUID(-1),
            teamID: UUID(-1),
            period: 1,
            elapsedSeconds: 20,
            points: 1,
            createdAt: startedAt
          )
        }
        try Team.find(UUID(-1)).update {
          $0.colorHex = #bind(updatedRavensColorHex)
        }
        .execute(db)
        try Team.find(UUID(-2)).update {
          $0.colorHex = #bind(updatedSwiftsColorHex)
        }
        .execute(db)
      }

      let values = try await database.read { db in
        (
          try GamesRequest().fetch(db),
          try TeamsRequest().fetch(db),
          try GameDetailRequest(gameID: UUID(-1)).fetch(db)
        )
      }

      expectNoDifference(values.0.games.map(\.teamABibColorHex), ["#30B0C7", "#AF52DE"])
      expectNoDifference(values.0.games.map(\.teamBBibColorHex), ["#FF2D55", "#FF9500"])
      expectNoDifference(values.1.teams.map(\.colorHex), ["#34C759", "#FF2D55"])
      expectNoDifference(values.2.detail?.teamABibColorHex, "#AF52DE")
      expectNoDifference(values.2.detail?.teamBBibColorHex, "#FF9500")
      expectNoDifference(
        values.2.detail?.goalTimeline.quarters.last?.goals.first?.scoringTeamBibColorHex,
        "#AF52DE"
      )
    }
  }
}
