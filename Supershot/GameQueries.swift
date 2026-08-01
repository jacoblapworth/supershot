import Foundation
import SQLiteData

nonisolated struct GameListItem: Equatable, Identifiable, Sendable {
  let endedAt: Date?
  let id: Game.ID
  let startedAt: Date
  let teamAName: String
  let teamAScore: Int
  let teamBName: String
  let teamBScore: Int

  var isCompleted: Bool {
    endedAt != nil
  }
}

nonisolated struct GoalTimelineItem: Equatable, Identifiable, Sendable {
  let clockSecondsRemaining: Int
  let id: Goal.ID
  let period: Int
  let points: Int
  let scoringTeamName: String
  let teamAScore: Int
  let teamBScore: Int
}

nonisolated struct CompletedGameDetail: Equatable, Identifiable, Sendable {
  let endedAt: Date
  let goals: [GoalTimelineItem]
  let id: Game.ID
  let startedAt: Date
  let teamAName: String
  let teamAScore: Int
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
          id: game.id,
          startedAt: game.startedAt,
          teamAName: teamA.name,
          teamAScore: gameGoals
            .filter { $0.teamID == teamA.id }
            .reduce(0) { $0 + $1.points },
          teamBName: teamB.name,
          teamBScore: gameGoals
            .filter { $0.teamID == teamB.id }
            .reduce(0) { $0 + $1.points }
        )
      }
    )
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
      let scoringTeamName: String
      if goal.teamID == snapshot.teamA.id {
        teamAScore += goal.points
        scoringTeamName = snapshot.teamA.name
      } else if goal.teamID == snapshot.teamB.id {
        teamBScore += goal.points
        scoringTeamName = snapshot.teamB.name
      } else {
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
        scoringTeamName: scoringTeamName,
        teamAScore: teamAScore,
        teamBScore: teamBScore
      )
    }

    return Value(
      detail: CompletedGameDetail(
        endedAt: endedAt,
        goals: timeline,
        id: snapshot.game.id,
        startedAt: snapshot.game.startedAt,
        teamAName: snapshot.teamA.name,
        teamAScore: teamAScore,
        teamBName: snapshot.teamB.name,
        teamBScore: teamBScore
      )
    )
  }
}

private nonisolated enum GameQueryError: Error {
  case gameNotFound
  case teamNotFound
}
