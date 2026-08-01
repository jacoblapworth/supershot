import Foundation
import SQLiteData

nonisolated struct GameListItem: Equatable, Identifiable, Sendable {
  let endedAt: Date?
  var firstBreakDurationSeconds = 0
  var halfTimeDurationSeconds = 0
  let id: Game.ID
  var periodDurationSeconds = 15 * 60
  var secondBreakDurationSeconds = 0
  let startedAt: Date
  var teamAColorHex = TeamColorPalette.blue
  let teamAName: String
  let teamAScore: Int
  var teamBColorHex = TeamColorPalette.red
  let teamBName: String
  let teamBScore: Int

  var isCompleted: Bool {
    endedAt != nil
  }

  var timingSummary: String {
    gameTimingSummary(
      periodDurationSeconds: periodDurationSeconds,
      firstBreakDurationSeconds: firstBreakDurationSeconds,
      halfTimeDurationSeconds: halfTimeDurationSeconds,
      secondBreakDurationSeconds: secondBreakDurationSeconds
    )
  }
}

nonisolated struct TeamListItem: Equatable, Identifiable, Sendable {
  let colorHex: String
  let gameCount: Int
  let id: Team.ID
  let name: String
}

nonisolated struct GoalTimelineItem: Equatable, Identifiable, Sendable {
  let clockSecondsRemaining: Int
  let id: Goal.ID
  let period: Int
  let points: Int
  var scoringTeamColorHex = TeamColorPalette.blue
  let scoringTeamName: String
  let teamAScore: Int
  let teamBScore: Int
}

nonisolated struct CompletedGameDetail: Equatable, Identifiable, Sendable {
  let endedAt: Date
  var firstBreakDurationSeconds = 0
  let goals: [GoalTimelineItem]
  var halfTimeDurationSeconds = 0
  let id: Game.ID
  var periodDurationSeconds = 15 * 60
  var secondBreakDurationSeconds = 0
  let startedAt: Date
  var teamAColorHex = TeamColorPalette.blue
  let teamAName: String
  let teamAScore: Int
  var teamBColorHex = TeamColorPalette.red
  let teamBName: String
  let teamBScore: Int

  var resultTitle: String {
    if teamAScore == teamBScore {
      return "Draw"
    } else if teamAScore > teamBScore {
      return "\(teamAName) win"
    } else {
      return "\(teamBName) win"
    }
  }

  var timingSummary: String {
    gameTimingSummary(
      periodDurationSeconds: periodDurationSeconds,
      firstBreakDurationSeconds: firstBreakDurationSeconds,
      halfTimeDurationSeconds: halfTimeDurationSeconds,
      secondBreakDurationSeconds: secondBreakDurationSeconds
    )
  }
}

nonisolated struct GameSnapshot: Equatable, Sendable {
  let game: Game
  let goals: [Goal]
  let teamA: Team
  let teamB: Team

  var teamAScore: Int {
    goals
      .filter { $0.teamID == teamA.id }
      .reduce(0) { $0 + $1.points }
  }

  var teamBScore: Int {
    goals
      .filter { $0.teamID == teamB.id }
      .reduce(0) { $0 + $1.points }
  }

  static func fetch(_ db: Database, gameID: Game.ID) throws -> Self {
    guard let game = try Game.find(gameID).fetchOne(db) else {
      throw GameQueryError.gameNotFound
    }
    guard
      let teamA = try Team.find(game.teamAID).fetchOne(db),
      let teamB = try Team.find(game.teamBID).fetchOne(db)
    else {
      throw GameQueryError.teamNotFound
    }

    let goals = try Goal
      .where { $0.gameID.eq(gameID) }
      .order { goals in (
        goals.period,
        goals.elapsedSeconds,
        goals.createdAt,
        goals.id
      ) }
      .fetchAll(db)

    return Self(game: game, goals: goals, teamA: teamA, teamB: teamB)
  }
}

nonisolated struct GamesRequest: FetchKeyRequest {
  struct Value: Equatable, Sendable {
    var games: [GameListItem] = []
  }

  func fetch(_ db: Database) throws -> Value {
    let games = try Game
      .order { games in (games.startedAt.desc(), games.id.desc()) }
      .fetchAll(db)
    let goals = try Goal.fetchAll(db)
    let teams = try Team.fetchAll(db)

    let goalsByGame = Dictionary(grouping: goals, by: \.gameID)
    let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

    return Value(
      games: games.compactMap { game in
        guard
          let teamA = teamsByID[game.teamAID],
          let teamB = teamsByID[game.teamBID]
        else { return nil }

        let gameGoals = goalsByGame[game.id, default: []]
        return GameListItem(
          endedAt: game.endedAt,
          firstBreakDurationSeconds: game.firstBreakDurationSeconds,
          halfTimeDurationSeconds: game.halfTimeDurationSeconds,
          id: game.id,
          periodDurationSeconds: game.periodDurationSeconds,
          secondBreakDurationSeconds: game.secondBreakDurationSeconds,
          startedAt: game.startedAt,
          teamAColorHex: teamA.colorHex,
          teamAName: teamA.name,
          teamAScore: gameGoals
            .filter { $0.teamID == teamA.id }
            .reduce(0) { $0 + $1.points },
          teamBColorHex: teamB.colorHex,
          teamBName: teamB.name,
          teamBScore: gameGoals
            .filter { $0.teamID == teamB.id }
            .reduce(0) { $0 + $1.points }
        )
      }
    )
  }
}

nonisolated struct TeamsRequest: FetchKeyRequest {
  struct Value: Equatable, Sendable {
    var teams: [TeamListItem] = []
  }

  func fetch(_ db: Database) throws -> Value {
    let games = try Game.fetchAll(db)
    let teams = try Team
      .order { ($0.normalizedName, $0.id) }
      .fetchAll(db)
    let gameCounts = games.reduce(into: [Team.ID: Int]()) { counts, game in
      for teamID in Set([game.teamAID, game.teamBID]) {
        counts[teamID, default: 0] += 1
      }
    }

    return Value(
      teams: teams.map { team in
        TeamListItem(
          colorHex: team.colorHex,
          gameCount: gameCounts[team.id, default: 0],
          id: team.id,
          name: team.name
        )
      }
    )
  }
}

nonisolated struct TeamDetailRequest: FetchKeyRequest {
  struct Value: Equatable, Sendable {
    var games: [GameListItem] = []
    var team: Team?
  }

  let teamID: Team.ID

  func fetch(_ db: Database) throws -> Value {
    guard let team = try Team.find(teamID).fetchOne(db) else {
      return Value()
    }
    let gameIDs = Set(
      try Game.fetchAll(db)
        .filter { $0.teamAID == teamID || $0.teamBID == teamID }
        .map(\.id)
    )
    let games = try GamesRequest().fetch(db).games
      .filter { gameIDs.contains($0.id) }
    return Value(games: games, team: team)
  }
}

nonisolated struct GameDetailRequest: FetchKeyRequest {
  struct Value: Equatable, Sendable {
    var detail: CompletedGameDetail?
  }

  let gameID: Game.ID

  func fetch(_ db: Database) throws -> Value {
    let snapshot = try GameSnapshot.fetch(db, gameID: gameID)
    guard let endedAt = snapshot.game.endedAt else { return Value() }

    var teamAScore = 0
    var teamBScore = 0
    let timeline = snapshot.goals.map { goal in
      let scoringTeamColorHex: String
      let scoringTeamName: String
      if goal.teamID == snapshot.teamA.id {
        teamAScore += goal.points
        scoringTeamColorHex = snapshot.teamA.colorHex
        scoringTeamName = snapshot.teamA.name
      } else if goal.teamID == snapshot.teamB.id {
        teamBScore += goal.points
        scoringTeamColorHex = snapshot.teamB.colorHex
        scoringTeamName = snapshot.teamB.name
      } else {
        scoringTeamColorHex = TeamColorPalette.blue
        scoringTeamName = "Unknown team"
      }

      return GoalTimelineItem(
        clockSecondsRemaining: max(
          snapshot.game.periodDurationSeconds - goal.elapsedSeconds,
          0
        ),
        id: goal.id,
        period: goal.period,
        points: goal.points,
        scoringTeamColorHex: scoringTeamColorHex,
        scoringTeamName: scoringTeamName,
        teamAScore: teamAScore,
        teamBScore: teamBScore
      )
    }

    return Value(
      detail: CompletedGameDetail(
        endedAt: endedAt,
        firstBreakDurationSeconds: snapshot.game.firstBreakDurationSeconds,
        goals: timeline,
        halfTimeDurationSeconds: snapshot.game.halfTimeDurationSeconds,
        id: snapshot.game.id,
        periodDurationSeconds: snapshot.game.periodDurationSeconds,
        secondBreakDurationSeconds: snapshot.game.secondBreakDurationSeconds,
        startedAt: snapshot.game.startedAt,
        teamAColorHex: snapshot.teamA.colorHex,
        teamAName: snapshot.teamA.name,
        teamAScore: teamAScore,
        teamBColorHex: snapshot.teamB.colorHex,
        teamBName: snapshot.teamB.name,
        teamBScore: teamBScore
      )
    )
  }
}

private nonisolated func gameTimingSummary(
  periodDurationSeconds: Int,
  firstBreakDurationSeconds: Int,
  halfTimeDurationSeconds: Int,
  secondBreakDurationSeconds: Int
) -> String {
  let quarter = formattedDuration(periodDurationSeconds)
  let breaks = [
    formattedDuration(firstBreakDurationSeconds),
    formattedDuration(halfTimeDurationSeconds),
    formattedDuration(secondBreakDurationSeconds),
  ]
  if Set(breaks).count == 1, let first = breaks.first {
    return "4 × \(quarter) · \(first) breaks"
  }
  return "4 × \(quarter) · breaks \(breaks.joined(separator: " / "))"
}

private nonisolated func formattedDuration(_ seconds: Int) -> String {
  let clampedSeconds = max(seconds, 0)
  return "\(clampedSeconds / 60):\(String(format: "%02d", clampedSeconds % 60))"
}

private nonisolated enum GameQueryError: Error {
  case gameNotFound
  case teamNotFound
}
