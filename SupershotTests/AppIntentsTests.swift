import AlarmClient
import AppIntents
import AppSettings
import Database
import Dependencies
import DependenciesTestSupport
import Foundation
import GameCore
import GameServices
import SharedModels
import Sharing
import SQLiteData
@testable import Supershot
import Testing
import WidgetSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
    $0.date.now = Date(timeIntervalSince1970: 1000)
  })
  struct AppIntentsTests {
    @Test func resolvesPlannedGameMetadataWithoutInventingAnActualStartDate() async throws {
      @Dependencies.Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let scheduledAt = Date(timeIntervalSince1970: 2000)
      try await database.write { db in
        try Team.insert {
          Team(id: UUID(1), name: "A")
          Team(id: UUID(2), name: "B")
        }.execute(db)
        try Game.insert {
          Game(
            id: UUID(3), startedAt: nil, teamAID: UUID(1), teamBID: UUID(2),
            createdAt: Date(timeIntervalSince1970: 1000), scheduledAt: scheduledAt, court: "A"
          )
        }.execute(db)
      }
      let entities = try await GameEntityQuery().entities(for: [UUID(3)])
      let entity = try #require(entities.first)
      #expect(entity.isPlanned)
      #expect(entity.startedAt == nil)
      #expect(entity.scheduledAt == scheduledAt)
      #expect(entity.court == "A")
      #expect(!entity.isCompleted)
    }

    @Test(arguments: [BreakStartPolicy.automatic, .manual])
    func createsPausedGameWithFourQuartersAndResolvesEntities(policy: BreakStartPolicy) async throws {
      @Dependencies.Dependency(\.defaultAppStorage) var defaults
      defaults.set(policy.rawValue, forKey: "defaultBreakStartPolicy")
      @Dependencies.Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let teamA = Team(id: UUID(-1), name: "Ravens", colorHex: "#34C759")
      let teamB = Team(id: UUID(-2), name: "Swifts", colorHex: "#FF9500")
      try await database.write { db in
        try Team.insert { teamA; teamB }.execute(db)
      }
      var intent = CreateGameIntent()
      intent.teamA = TeamEntity(team: teamA)
      intent.teamB = TeamEntity(team: teamB)
      intent.firstCentrePass = TeamEntity(team: teamB)
      intent.quarterDurationSeconds = 600
      intent.breakDurationSeconds = 0
      let result = try await intent.perform()
      let entity = try #require(result.value)
      let games = try await database.read { try Game.fetchAll($0) }
      let game = try #require(games.first)
      #expect(game.breakStartPolicy == policy)
      #expect(games.count == 1)
      #expect(entity.id == game.id)
      #expect(game.centrePassTeamID == teamB.id)
      #expect(game.timerEndsAt == nil)
      #expect(game.elapsedSeconds == 0)
      #expect(game.startedAt == nil)
      #expect(game.createdAt == Date(timeIntervalSince1970: 1000))
      #expect(game.teamABibColorHex == teamA.colorHex)
      #expect(game.teamBBibColorHex == teamB.colorHex)
      let periods = try await database.read {
        try GamePeriod.order(by: \.position).fetchAll($0)
      }
      #expect(periods.map(\.position) == [0, 1, 2, 3])
      #expect(periods.allSatisfy { $0.gameID == game.id && $0.durationSeconds == 600 })
      #expect(periods.map(\.breakAfterDurationSeconds) == [nil, nil, nil, nil])
      #expect(GameTimeline(periods: periods)?.phases.count == 4)
      #expect(try await GameEntityQuery().entities(for: [game.id, UUID(-99)]).map(\.id) == [game.id])
      #expect(try await GameEntityQuery().entities(matching: "Ravens").map(\.id) == [game.id])
      #expect(try await GameEntityQuery().entities(matching: "Missing").isEmpty)
      #expect(try await GameEntityQuery().suggestedEntities().map(\.id) == [game.id])
      #expect(try await TeamEntityQuery().entities(for: [teamA.id, UUID(-99)]).map(\.id) == [teamA.id])
      #expect(try await TeamEntityQuery().entities(matching: "rav").map(\.id) == [teamA.id])
      #expect(try await TeamEntityQuery().suggestedEntities().map(\.id) == [teamA.id, teamB.id])
      try await database.write { db in
        try Team.where { $0.id.eq(teamA.id) }.update { $0.name = "Falcons" }.execute(db)
      }
      let refreshed = try await GameEntityQuery().entities(for: [game.id])
      #expect(refreshed.first?.teamA.name == "Falcons")
    }

    @Test(arguments: ["duplicate", "centrePass", "quarter", "break", "deleted"])
    func invalidInputDoesNotCreateGame(scenario: String) async throws {
      @Dependencies.Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let teamA = Team(id: UUID(-1), name: "Ravens")
      let teamB = Team(id: UUID(-2), name: "Swifts")
      try await database.write { db in
        try Team.insert { teamA; teamB }.execute(db)
      }
      var intent = CreateGameIntent()
      intent.teamA = TeamEntity(team: teamA)
      intent.teamB = TeamEntity(team: teamB)
      intent.firstCentrePass = TeamEntity(team: teamA)
      intent.quarterDurationSeconds = 480
      intent.breakDurationSeconds = 60
      switch scenario {
      case "duplicate": intent.teamB = intent.teamA
      case "centrePass":
        intent.firstCentrePass = TeamEntity(team: Team(id: UUID(-3), name: "Owls"))
      case "quarter": intent.quarterDurationSeconds = 0
      case "break": intent.breakDurationSeconds = -1
      default:
        try await database.write { db in
          try Team.where { $0.id.eq(teamB.id) }.delete().execute(db)
        }
      }
      await #expect(throws: CreateGameError.self) { try await intent.perform() }
      #expect(try await database.read { try Game.fetchAll($0).isEmpty })
      #expect(try await database.read { try GamePeriod.fetchAll($0).isEmpty })
    }
  }
}
