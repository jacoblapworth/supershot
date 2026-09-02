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
  }) struct TeamDetailFeatureTests {
    @Test
    func teamDetailShowsOnlyTheTeamsGamesNewestFirst() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      let olderDate = Date(timeIntervalSince1970: 1_000)
      let newerDate = Date(timeIntervalSince1970: 2_000)
      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
          Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
          Team(id: UUID(-3), name: "Aces", colorHex: "#34C759")
          Game(
            id: UUID(-1),
            startedAt: olderDate,
            endedAt: Date(timeIntervalSince1970: 1_500),
            teamAID: UUID(-1),
            teamBID: UUID(-2)
          )
          Game(
            id: UUID(-2),
            startedAt: newerDate,
            endedAt: nil,
            teamAID: UUID(-3),
            teamABibColorHex: "#34C759",
            teamBID: UUID(-1),
            teamBBibColorHex: TeamColorPalette.blue
          )
          Game(
            id: UUID(-3),
            startedAt: Date(timeIntervalSince1970: 3_000),
            endedAt: nil,
            teamAID: UUID(-2),
            teamBID: UUID(-3)
          )
        }
        let periods = [
          testGamePeriods(gameID: UUID(-1), durationSeconds: 900),
          testGamePeriods(gameID: UUID(-2), durationSeconds: 600),
          testGamePeriods(gameID: UUID(-3), durationSeconds: 900),
        ].flatMap { $0 }
        try GamePeriod.insert { periods }.execute(db)
        try Goal.insert {
          Goal(
            id: UUID(-1),
            gameID: UUID(-1),
            gamePeriodID: testGamePeriodID(gameID: UUID(-1), position: 0),
            teamID: UUID(-1),
            elapsedSeconds: 10,
            points: 2,
            createdAt: olderDate
          )
          Goal(
            id: UUID(-2),
            gameID: UUID(-2),
            gamePeriodID: testGamePeriodID(gameID: UUID(-2), position: 0),
            teamID: UUID(-3),
            elapsedSeconds: 20,
            points: 1,
            createdAt: newerDate
          )
        }
        .execute(db)
      }

      let value = try await database.read { db in
        try TeamDetailRequest(teamID: UUID(-1)).fetch(db)
      }

      expectNoDifference(
        value,
        TeamDetailRequest.Value(
          games: [
            GameListItem(
              endedAt: nil,
              id: UUID(-2),
              periods: testGamePeriods(gameID: UUID(-2), durationSeconds: 600),
              startedAt: newerDate,
              teamABibColorHex: "#34C759",
              teamAName: "Aces",
              teamAScore: 1,
              teamBBibColorHex: TeamColorPalette.blue,
              teamBName: "Ravens",
              teamBScore: 0
            ),
            GameListItem(
              endedAt: Date(timeIntervalSince1970: 1_500),
              id: UUID(-1),
              periods: testGamePeriods(gameID: UUID(-1), durationSeconds: 900),
              startedAt: olderDate,
              teamABibColorHex: TeamColorPalette.blue,
              teamAName: "Ravens",
              teamAScore: 2,
              teamBBibColorHex: TeamColorPalette.red,
              teamBName: "Swifts",
              teamBScore: 0
            ),
          ],
          team: Team(
            id: UUID(-1),
            name: "Ravens",
            colorHex: TeamColorPalette.blue
          )
        )
      )
    }
  }
}
