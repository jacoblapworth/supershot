@testable import AlarmClient
@testable import AppSettings
import CustomDump
@testable import Database
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import GameAnalysis
@testable import GameCore
@testable import GameDetailFeature
@testable import GameServices
import GRDB
@testable import LocationClient
@testable import NewGameFeature
@testable import PaywallFeature
@testable import PermissionsFeature
@testable import PreviewSupport
@testable import ScoringFeature
@testable import SharedModels
@testable import SoundEffectsClient
import SQLiteData
@testable import Styleguide
@testable import SubscriptionClient
import SwiftUI
@testable import TeamEditingFeature
@testable import TeamsFeature
import Testing
import TestSupport
@testable import WidgetSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
  }) struct TeamDetailFeatureTests {
    @Test
    func teamDetailShowsOnlyTheTeamsGamesNewestFirst() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)

      let olderDate = Date(timeIntervalSince1970: 1000)
      let newerDate = Date(timeIntervalSince1970: 2000)
      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens", colorHex: ColorPalette.blue.hex())
          Team(id: UUID(-2), name: "Swifts", colorHex: ColorPalette.red.hex())
          Team(id: UUID(-3), name: "Aces", colorHex: "#34C759")
          Game(
            id: UUID(-1),
            startedAt: olderDate,
            endedAt: Date(timeIntervalSince1970: 1500),
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
            teamBBibColorHex: ColorPalette.blue.hex()
          )
          Game(
            id: UUID(-3),
            startedAt: Date(timeIntervalSince1970: 3000),
            endedAt: nil,
            teamAID: UUID(-2),
            teamBID: UUID(-3)
          )
        }
        let periods = [
          testGamePeriods(gameID: UUID(-1), durationSeconds: 900),
          testGamePeriods(gameID: UUID(-2), durationSeconds: 600),
          testGamePeriods(gameID: UUID(-3), durationSeconds: 900),
        ].flatMap(\.self)
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
              teamABibColor: Color(hex: "#34C759"),
              teamAName: "Aces",
              teamAScore: 1,
              teamBBibColor: ColorPalette.blue,
              teamBName: "Ravens",
              teamBScore: 0
            ),
            GameListItem(
              endedAt: Date(timeIntervalSince1970: 1500),
              id: UUID(-1),
              periods: testGamePeriods(gameID: UUID(-1), durationSeconds: 900),
              startedAt: olderDate,
              teamABibColor: ColorPalette.blue,
              teamAName: "Ravens",
              teamAScore: 2,
              teamBBibColor: ColorPalette.red,
              teamBName: "Swifts",
              teamBScore: 0
            ),
          ],
          team: Team(
            id: UUID(-1),
            name: "Ravens",
            colorHex: ColorPalette.blue.hex()
          ),
          statistics: TeamStatistics(wins: 1, pointsScored: 2)
        )
      )
    }

    @Test
    func statisticsUseCompletedGamesAndParticipantIDs() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let date = Date(timeIntervalSince1970: 1000)
      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens")
          Team(id: UUID(-2), name: "Ravens")
          Team(id: UUID(-3), name: "Other")
        }
        for index in 1 ... 6 {
          let gameID = UUID(-index)
          try Game.insert {
            Game(
              id: gameID, startedAt: date,
              endedAt: index == 5 ? nil : date.addingTimeInterval(100),
              teamAID: index == 6 ? UUID(-3) : (index == 2 ? UUID(-2) : UUID(-1)),
              teamBID: index == 2 ? UUID(-1) : UUID(-2)
            )
          }.execute(db)
          try GamePeriod.insert {
            testGamePeriods(gameID: gameID, durationSeconds: 600)
          }.execute(db)
        }
        let scoring: [(Int, Int, Int)] = [
          (1, -1, 2), (1, -1, 1), (1, -2, 1), (1, -3, 100),
          (2, -1, 1), (2, -2, 2),
          (3, -1, 2), (3, -2, 2),
          (5, -1, 100), (6, -2, 100),
        ]
        for (index, event) in scoring.enumerated() {
          try Goal.insert {
            Goal(
              id: UUID(-index - 1), gameID: UUID(-event.0),
              gamePeriodID: testGamePeriodID(gameID: UUID(-event.0), position: 0),
              teamID: UUID(event.1), elapsedSeconds: index,
              points: event.2, createdAt: date
            )
          }.execute(db)
        }
      }
      let request = TeamDetailRequest(teamID: UUID(-1))
      let value = try await database.read { try request.fetch($0) }
      expectNoDifference(
        value.statistics,
        TeamStatistics(wins: 1, losses: 1, draws: 2, pointsScored: 6, pointsAgainst: 5)
      )
      #expect(value.statistics.gamesPlayed == 4)
      #expect(value.statistics.pointsDifference == 1)
      #expect(value.statistics.winRate == 0.25)
      #expect(value.games.count == 5)

      try await database.write { db in
        try Team.find(UUID(-1)).update {
          $0.name = "Renamed"
          $0.colorHex = "#34C759"
        }.execute(db)
      }
      let renamed = try await database.read { try request.fetch($0) }
      expectNoDifference(renamed.statistics, value.statistics)
      #expect(renamed.team?.name == "Renamed")
    }

    @Test
    func statisticsObserveFinishingScoringAndDeletingGames() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let date = Date(timeIntervalSince1970: 1000)
      try await database.write { db in
        try db.seed {
          Team(id: UUID(-1), name: "Ravens")
          Team(id: UUID(-2), name: "Swifts")
          Game(id: UUID(-1), startedAt: date, teamAID: UUID(-1), teamBID: UUID(-2))
        }
        try GamePeriod.insert {
          testGamePeriods(gameID: UUID(-1), durationSeconds: 600)
        }.execute(db)
      }
      let request = TeamDetailRequest(teamID: UUID(-1))
      var updates = ValueObservation.tracking { db in
        try request.fetch(db)
      }.values(in: database).makeAsyncIterator()
      let initial = try #require(await updates.next())
      expectNoDifference(initial.statistics, TeamStatistics())
      #expect(initial.statistics.winRate == nil)
      #expect(initial.games.count == 1)

      try await database.write { db in
        try Game.find(UUID(-1)).update {
          $0.endedAt = #bind(date.addingTimeInterval(100))
        }.execute(db)
      }
      let finished = try #require(await updates.next())
      expectNoDifference(finished.statistics, TeamStatistics(draws: 1))
      #expect(finished.statistics.winRate == 0)

      try await database.write { db in
        try Goal.insert {
          Goal(
            id: UUID(-1), gameID: UUID(-1),
            gamePeriodID: testGamePeriodID(gameID: UUID(-1), position: 0),
            teamID: UUID(-2), elapsedSeconds: 10, points: 2, createdAt: date
          )
        }.execute(db)
      }
      let scored = try #require(await updates.next())
      expectNoDifference(scored.statistics, TeamStatistics(losses: 1, pointsAgainst: 2))
      #expect(scored.statistics.pointsDifference == -2)

      try await database.write { db in
        try Game.find(UUID(-1)).delete().execute(db)
      }
      let deleted = try #require(await updates.next())
      expectNoDifference(deleted.statistics, TeamStatistics())
      #expect(deleted.games.isEmpty)
    }

    @Test
    func emptyAndMissingTeamsHaveNoStatistics() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      try await database.write { db in
        try Team.insert { Team(id: UUID(-1), name: "Ravens") }.execute(db)
      }
      let empty = try await database.read { try TeamDetailRequest(teamID: UUID(-1)).fetch($0) }
      expectNoDifference(empty.statistics, TeamStatistics())
      #expect(empty.statistics.winRate == nil)
      #expect(empty.games.isEmpty)
      #expect(empty.team != nil)
      let missing = try await database.read { try TeamDetailRequest(teamID: UUID(-2)).fetch($0) }
      expectNoDifference(missing, TeamDetailRequest.Value())
    }
  }
}
