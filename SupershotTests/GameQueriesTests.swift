import SwiftUI
import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import Supershot
import DependenciesTestSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
  }) struct GameQueriesTests {
    @Test(.dependencies {
      $0.uuid = .incrementing
    })
    func gameListIsNewestFirstWithScoresAndStatuses() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      let olderDate = Date(timeIntervalSince1970: 1_000)
      let newerDate = Date(timeIntervalSince1970: 2_000)
      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens", colorHex: ColorPalette.blue.hex())
          Team(id: UUID(-2), name: "Swifts", colorHex: ColorPalette.red.hex())
          Team(id: UUID(-3), name: "Foxes", colorHex: "#34C759")
          Team(id: UUID(-4), name: "Owls", colorHex: "#FF9500")
          Game(
            id: UUID(-1),
            startedAt: newerDate,
            endedAt: nil,
            teamAID: UUID(-1),
            teamBID: UUID(-2),
            currentPhaseIndex: 2
          )
          Game(
            id: UUID(-2),
            startedAt: olderDate,
            endedAt: Date(timeIntervalSince1970: 1_500),
            teamAID: UUID(-3),
            teamABibColorHex: "#34C759",
            teamBID: UUID(-4),
            teamBBibColorHex: "#FF9500"
          )
        }
        let firstPeriods = testGamePeriods(
          gameID: UUID(-1),
          durationSeconds: 900,
          breakDurations: [240, 600, 240]
        )
        let secondPeriods = testGamePeriods(gameID: UUID(-2), durationSeconds: 900)
        try GamePeriod.insert { firstPeriods; secondPeriods }.execute(db)
        try Goal.insert {
          Goal(
            id: UUID(-1),
            gameID: UUID(-1),
            gamePeriodID: firstPeriods[0].id,
            teamID: UUID(-1),
            elapsedSeconds: 10,
            points: 2,
            createdAt: newerDate
          )
          Goal(
            id: UUID(-2),
            gameID: UUID(-2),
            gamePeriodID: secondPeriods[0].id,
            teamID: UUID(-4),
            elapsedSeconds: 20,
            points: 1,
            createdAt: olderDate
          )
        }
        .execute(db)
      }

      let value = try await database.read { db in
        try GamesRequest().fetch(db)
      }

      expectNoDifference(
        value.games,
        [
          GameListItem(
            currentQuarter: 2,
            endedAt: nil,
            id: UUID(-1),
            periods: testGamePeriods(
              gameID: UUID(-1),
              durationSeconds: 900,
              breakDurations: [240, 600, 240]
            ),
            startedAt: newerDate,
            teamABibColor: ColorPalette.blue,
            teamAName: "Ravens",
            teamAScore: 2,
            teamBBibColor: ColorPalette.red,
            teamBName: "Swifts",
            teamBScore: 0
          ),
          GameListItem(
            endedAt: Date(timeIntervalSince1970: 1_500),
            id: UUID(-2),
            periods: testGamePeriods(gameID: UUID(-2), durationSeconds: 900),
            startedAt: olderDate,
            teamABibColor: Color(hex: "#34C759"),
            teamAName: "Foxes",
            teamAScore: 0,
            teamBBibColor: Color(hex: "#FF9500"),
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
          Team(id: UUID(-1), name: "Ravens", colorHex: ColorPalette.blue.hex())
          Team(id: UUID(-2), name: "Swifts", colorHex: ColorPalette.red.hex())
          Game(
            id: UUID(-1),
            startedAt: startedAt,
            endedAt: Date(timeIntervalSince1970: 2_000),
            teamAID: UUID(-1),
            teamABibColorHex: "#AF52DE",
            teamBID: UUID(-2),
            teamBBibColorHex: "#FF9500"
          )
          Game(
            id: UUID(-2),
            startedAt: Date(timeIntervalSince1970: 3_000),
            endedAt: nil,
            teamAID: UUID(-1),
            teamABibColorHex: "#30B0C7",
            teamBID: UUID(-2),
            teamBBibColorHex: "#FF2D55"
          )
        }
        let firstPeriods = testGamePeriods(gameID: UUID(-1), durationSeconds: 900)
        let secondPeriods = testGamePeriods(gameID: UUID(-2), durationSeconds: 900)
        try GamePeriod.insert { firstPeriods; secondPeriods }.execute(db)
        try Goal.insert {
          Goal(
            id: UUID(-1),
            gameID: UUID(-1),
            gamePeriodID: firstPeriods[0].id,
            teamID: UUID(-1),
            elapsedSeconds: 20,
            points: 1,
            createdAt: startedAt
          )
        }
        .execute(db)
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

      expectNoDifference(values.0.games.map(\.teamABibColor), [ColorPalette.teal, ColorPalette.purple])
      expectNoDifference(values.0.games.map(\.teamBBibColor), [ColorPalette.pink, ColorPalette.orange])
      expectNoDifference(values.1.teams.map(\.color), [ColorPalette.green, ColorPalette.pink])
      expectNoDifference(values.2.detail?.teamABibColor, ColorPalette.purple)
      expectNoDifference(values.2.detail?.teamBBibColor, ColorPalette.orange)
      expectNoDifference(
        values.2.detail?.goalTimeline.quarters.last?.goals.first?.scoringTeamBibColor,
        ColorPalette.purple
      )
    }
  }
}
