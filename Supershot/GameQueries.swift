import Foundation
import SQLiteData

nonisolated struct GameListItem: Equatable, Identifiable, Sendable {
  var currentQuarter = 1
  let endedAt: Date?
  var firstBreakDurationSeconds = 0
  var halfTimeDurationSeconds = 0
  let id: Game.ID
  var periodDurationSeconds = 15 * 60
  var secondBreakDurationSeconds = 0
  let startedAt: Date
  var teamABibColorHex = TeamColorPalette.blue
  let teamAName: String
  let teamAScore: Int
  var teamBBibColorHex = TeamColorPalette.red
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

nonisolated struct GoalTimeline: Equatable, Sendable {
  var quarters: [GoalTimelineQuarter] = []

  static func empty(through period: Int) -> Self {
    let finalPeriod = min(max(period, 1), 4)
    return Self(
      quarters: (1...finalPeriod).reversed().map {
        GoalTimelineQuarter(
          goals: [],
          period: $0,
          teamAQuarterScore: 0,
          teamBQuarterScore: 0
        )
      }
    )
  }
}

nonisolated struct GoalTimelineQuarter: Equatable, Identifiable, Sendable {
  var id: Int { period }
  let goals: [GoalTimelineItem]
  let period: Int
  let teamAQuarterScore: Int
  let teamBQuarterScore: Int
}

nonisolated enum GoalTimelineTeamSide: Equatable, Sendable {
  case teamA
  case teamB
  case unknown
}

nonisolated struct GoalTimelineItem: Equatable, Identifiable, Sendable {
  let clockSecondsRemaining: Int
  let id: Goal.ID
  let period: Int
  let points: Int
  var scoringTeamBibColorHex = TeamColorPalette.blue
  let scoringTeamName: String
  let scoringTeamSide: GoalTimelineTeamSide
  let teamAScore: Int
  let teamBScore: Int
}

nonisolated struct CentrePassStatistics: Equatable, Sendable {
  let conversions: Int
  let inferredTurnovers: Int
  let opportunities: Int
}

nonisolated struct TeamGameStatistics: Equatable, Sendable {
  var averageTimeToGoalSeconds: Double?
  var centrePass: CentrePassStatistics?
}

nonisolated struct CompletedGameStatistics: Equatable, Sendable {
  var teamA = TeamGameStatistics()
  var teamB = TeamGameStatistics()
}

nonisolated struct CompletedGameDetail: Equatable, Identifiable, Sendable {
  let endedAt: Date
  var firstBreakDurationSeconds = 0
  let goalTimeline: GoalTimeline
  var halfTimeDurationSeconds = 0
  let id: Game.ID
  var periodDurationSeconds = 15 * 60
  var secondBreakDurationSeconds = 0
  let startedAt: Date
  var statistics = CompletedGameStatistics()
  var teamABibColorHex = TeamColorPalette.blue
  let teamAName: String
  let teamAScore: Int
  var teamBBibColorHex = TeamColorPalette.red
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
        goals.quarterNumber,
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
          currentQuarter: game.currentPhase.quarterNumber,
          endedAt: game.endedAt,
          firstBreakDurationSeconds: game.firstBreakDurationSeconds,
          halfTimeDurationSeconds: game.halfTimeDurationSeconds,
          id: game.id,
          periodDurationSeconds: game.periodDurationSeconds,
          secondBreakDurationSeconds: game.secondBreakDurationSeconds,
          startedAt: game.startedAt,
          teamABibColorHex: game.teamABibColorHex,
          teamAName: teamA.name,
          teamAScore: gameGoals
            .filter { $0.teamID == teamA.id }
            .reduce(0) { $0 + $1.points },
          teamBBibColorHex: game.teamBBibColorHex,
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
      .order { ($0.name, $0.id) }
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

nonisolated struct GoalTimelineRequest: FetchKeyRequest {
  struct Value: Equatable, Sendable {
    var timeline = GoalTimeline()
  }

  let gameID: Game.ID

  func fetch(_ db: Database) throws -> Value {
    Value(
      timeline: goalTimeline(
        snapshot: try GameSnapshot.fetch(db, gameID: gameID)
      )
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
    let timeline = goalTimeline(snapshot: snapshot)

    return Value(
      detail: CompletedGameDetail(
        endedAt: endedAt,
        firstBreakDurationSeconds: snapshot.game.firstBreakDurationSeconds,
        goalTimeline: timeline,
        halfTimeDurationSeconds: snapshot.game.halfTimeDurationSeconds,
        id: snapshot.game.id,
        periodDurationSeconds: snapshot.game.periodDurationSeconds,
        secondBreakDurationSeconds: snapshot.game.secondBreakDurationSeconds,
        startedAt: snapshot.game.startedAt,
        statistics: completedGameStatistics(
          goals: snapshot.goals,
          teamAID: snapshot.teamA.id,
          teamBID: snapshot.teamB.id
        ),
        teamABibColorHex: snapshot.game.teamABibColorHex,
        teamAName: snapshot.teamA.name,
        teamAScore: snapshot.teamAScore,
        teamBBibColorHex: snapshot.game.teamBBibColorHex,
        teamBName: snapshot.teamB.name,
        teamBScore: snapshot.teamBScore
      )
    )
  }
}

private nonisolated func goalTimeline(snapshot: GameSnapshot) -> GoalTimeline {
  var goalsByPeriod: [Int: [GoalTimelineItem]] = [:]
  var quarterScoresByPeriod: [Int: (teamA: Int, teamB: Int)] = [:]
  var teamAScore = 0
  var teamBScore = 0

  for goal in snapshot.goals {
    let scoringTeamBibColorHex: String
    let scoringTeamName: String
    let scoringTeamSide: GoalTimelineTeamSide

    if goal.teamID == snapshot.teamA.id {
      teamAScore += goal.points
      quarterScoresByPeriod[goal.quarterNumber, default: (0, 0)].teamA += goal.points
      scoringTeamBibColorHex = snapshot.game.teamABibColorHex
      scoringTeamName = snapshot.teamA.name
      scoringTeamSide = .teamA
    } else if goal.teamID == snapshot.teamB.id {
      teamBScore += goal.points
      quarterScoresByPeriod[goal.quarterNumber, default: (0, 0)].teamB += goal.points
      scoringTeamBibColorHex = snapshot.game.teamBBibColorHex
      scoringTeamName = snapshot.teamB.name
      scoringTeamSide = .teamB
    } else {
      scoringTeamBibColorHex = TeamColorPalette.blue
      scoringTeamName = "Unknown team"
      scoringTeamSide = .unknown
    }

    goalsByPeriod[goal.quarterNumber, default: []].append(
      GoalTimelineItem(
        clockSecondsRemaining: max(
          snapshot.game.periodDurationSeconds - goal.elapsedSeconds,
          0
        ),
        id: goal.id,
        period: goal.quarterNumber,
        points: goal.points,
        scoringTeamBibColorHex: scoringTeamBibColorHex,
        scoringTeamName: scoringTeamName,
        scoringTeamSide: scoringTeamSide,
        teamAScore: teamAScore,
        teamBScore: teamBScore
      )
    )
  }

  let maximumPeriod = 4
  let playedPeriod = snapshot.game.endedAt == nil
    ? min(
      max(
        snapshot.game.currentPhase.quarterNumber,
        snapshot.goals.map(\.quarterNumber).max() ?? 1
      ),
      maximumPeriod
    )
    : maximumPeriod

  return GoalTimeline(
    quarters: (1...max(playedPeriod, 1)).reversed().map { period in
      let quarterScore = quarterScoresByPeriod[period, default: (0, 0)]
      return GoalTimelineQuarter(
        goals: Array(goalsByPeriod[period, default: []].reversed()),
        period: period,
        teamAQuarterScore: quarterScore.teamA,
        teamBQuarterScore: quarterScore.teamB
      )
    }
  )
}

private nonisolated func completedGameStatistics(
  goals: [Goal],
  teamAID: Team.ID,
  teamBID: Team.ID
) -> CompletedGameStatistics {
  var goalDurationsByTeamID: [Team.ID: [Int]] = [:]
  var previousGoalElapsedSecondsByPeriod: [Int: Int] = [:]

  for goal in goals {
    let previousElapsedSeconds = previousGoalElapsedSecondsByPeriod[goal.quarterNumber, default: 0]
    let duration = max(goal.elapsedSeconds - previousElapsedSeconds, 0)
    previousGoalElapsedSecondsByPeriod[goal.quarterNumber] = goal.elapsedSeconds

    if goal.teamID == teamAID || goal.teamID == teamBID {
      goalDurationsByTeamID[goal.teamID, default: []].append(duration)
    }
  }

  let hasCompleteCentrePassData = goals.allSatisfy { goal in
    (goal.teamID == teamAID || goal.teamID == teamBID)
      && (goal.centrePassTeamID == teamAID || goal.centrePassTeamID == teamBID)
  }

  func centrePassStatistics(for teamID: Team.ID) -> CentrePassStatistics? {
    guard hasCompleteCentrePassData else { return nil }
    let opportunities = goals.filter { $0.centrePassTeamID == teamID }
    return CentrePassStatistics(
      conversions: opportunities.count { $0.teamID == teamID },
      inferredTurnovers: opportunities.count { $0.teamID != teamID },
      opportunities: opportunities.count
    )
  }

  func teamStatistics(for teamID: Team.ID) -> TeamGameStatistics {
    let durations = goalDurationsByTeamID[teamID, default: []]
    return TeamGameStatistics(
      averageTimeToGoalSeconds: durations.isEmpty
        ? nil
        : Double(durations.reduce(0, +)) / Double(durations.count),
      centrePass: centrePassStatistics(for: teamID)
    )
  }

  return CompletedGameStatistics(
    teamA: teamStatistics(for: teamAID),
    teamB: teamStatistics(for: teamBID)
  )
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
