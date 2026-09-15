import AppIntents
import Dependencies
import Foundation
import SQLiteData

struct CreateGameIntent: AppIntent {
  static let title: LocalizedStringResource = "Create Game"
  static let description = IntentDescription(
    "Create a game with four quarters. The timer stays paused until you start it in Supershot."
  )
  static var supportedModes: IntentModes { .background }
  static var allowedExecutionTargets: IntentExecutionTargets { .main }

  @Parameter(title: "Team A") var teamA: TeamEntity
  @Parameter(title: "Team B") var teamB: TeamEntity
  @Parameter(title: "First Centre Pass") var firstCentrePass: TeamEntity
  @Parameter(title: "Quarter Duration (seconds)", default: 480, inclusiveRange: (1, 5999))
  var quarterDurationSeconds: Int
  @Parameter(title: "Break Duration (seconds)", default: 60, inclusiveRange: (0, 5999))
  var breakDurationSeconds: Int

  static var parameterSummary: some ParameterSummary {
    Summary("Create a game between \(\.$teamA) and \(\.$teamB)") {
      \.$firstCentrePass
      \.$quarterDurationSeconds
      \.$breakDurationSeconds
    }
  }

  @Dependencies.Dependency(\.defaultDatabase) private var database
  @Dependencies.Dependency(\.date.now) private var now
  @Dependencies.Dependency(\.uuid) private var uuid

  func perform() async throws -> some IntentResult & ReturnsValue<GameEntity> {
    guard teamA.id != teamB.id else { throw CreateGameError.duplicateTeams }
    guard firstCentrePass.id == teamA.id || firstCentrePass.id == teamB.id else {
      throw CreateGameError.invalidCentrePass
    }
    guard (1...5999).contains(quarterDurationSeconds),
      (0...5999).contains(breakDurationSeconds)
    else { throw CreateGameError.invalidDuration }

    let gameID = uuid()
    let startedAt = now
    let teamAID = teamA.id
    let teamBID = teamB.id
    let centrePassID = firstCentrePass.id
    let periods = (0..<4).map { position in
      GamePeriod(
        id: uuid(), gameID: gameID, position: position,
        durationSeconds: quarterDurationSeconds,
        breakAfterDurationSeconds: position < 3 ? breakDurationSeconds : nil
      )
    }
    let entity = try await database.write { db in
      let teamIDs = [teamAID, teamBID]
      let teams = try Team.where { $0.id.in(teamIDs) }.fetchAll(db)
      guard let teamA = teams.first(where: { $0.id == teamAID }),
        let teamB = teams.first(where: { $0.id == teamBID })
      else { throw CreateGameError.teamUnavailable }
      let game = Game(
        id: gameID, startedAt: startedAt, teamAID: teamAID,
        teamABibColorHex: teamA.colorHex, teamBID: teamBID,
        teamBBibColorHex: teamB.colorHex, centrePassTeamID: centrePassID
      )
      try Game.insert { game }.execute(db)
      try GamePeriod.insert { periods }.execute(db)
      return GameEntity(game: game, teamA: teamA, teamB: teamB)
    }
    return .result(value: entity)
  }
}

nonisolated enum CreateGameError: Error, CustomLocalizedStringResourceConvertible {
  case duplicateTeams
  case invalidCentrePass
  case invalidDuration
  case teamUnavailable

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .duplicateTeams: "Choose two different teams."
    case .invalidCentrePass: "The first centre pass must belong to one of the game's teams."
    case .invalidDuration: "Quarter durations must be 1–5999 seconds and breaks 0–5999 seconds."
    case .teamUnavailable: "A selected team no longer exists. Choose the teams again."
    }
  }
}
