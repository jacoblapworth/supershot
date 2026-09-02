import Foundation
import SQLiteData

nonisolated struct GameListItem: Equatable, Identifiable, Sendable {
  var currentQuarter = 1
  let endedAt: Date?
  let id: Game.ID
  var periods: [GamePeriod] = []
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
    gameTimingSummary(periods: periods)
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
    let finalPeriod = max(period, 1)
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
  let goalTimeline: GoalTimeline
  let id: Game.ID
  var location: GameLocation?
  var periods: [GamePeriod] = []
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
    gameTimingSummary(periods: periods)
  }
}

/// A nonisolated, immutable snapshot of all state needed to reason about a single game at a point in time.
///
/// GameSnapshot aggregates the core records for a game so that higher–level
/// queries, computed properties, and presentation logic can be performed without
/// repeatedly hitting the database. It bundles the `Game` row itself, the
/// participating `Team`s, all `GamePeriod`s (quarters and breaks), and every
/// `Goal` that has been recorded for the game. From those inputs it derives
/// useful, read‑only facts such as the current phase, current period, whether the
/// final period has completed, and each team’s total score.
///
nonisolated struct GameSnapshot: Equatable, Sendable {
  let game: Game
  let goals: [Goal]
  let periods: [GamePeriod]
  let teamA: Team
  let teamB: Team

  var phases: [GamePhase] { gamePhases(for: periods) }

  var currentPhase: GamePhase {
    let phases = phases
    guard !phases.isEmpty else {
      return .period(number: 1, durationSeconds: 0)
    }
    return phases[min(max(game.currentPhaseIndex, 0), phases.count - 1)]
  }

  var currentPeriod: GamePeriod? {
    periods.first { $0.number == currentPhase.periodNumber }
  }

  var isFinalPeriodComplete: Bool {
    game.currentPhaseIndex == phases.count - 1
      && currentPhase.isQuarter
      && game.elapsedSeconds >= currentPhase.durationSeconds
      && game.timerEndsAt == nil
  }

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

    let periods = try GamePeriod
      .where { $0.gameID.eq(gameID) }
      .order { ($0.position, $0.id) }
      .fetchAll(db)
    guard !periods.isEmpty else {
      throw GameQueryError.periodsNotFound
    }

    let unsortedGoals = try Goal
      .where { $0.gameID.eq(gameID) }
      .fetchAll(db)
    let positionsByPeriodID = Dictionary(
      uniqueKeysWithValues: periods.map { ($0.id, $0.position) }
    )
    let goals = unsortedGoals.sorted {
      (
        positionsByPeriodID[$0.gamePeriodID] ?? .max,
        $0.elapsedSeconds,
        $0.createdAt,
        $0.id
      ) < (
        positionsByPeriodID[$1.gamePeriodID] ?? .max,
        $1.elapsedSeconds,
        $1.createdAt,
        $1.id
      )
    }

    return Self(
      game: game,
      goals: goals,
      periods: periods,
      teamA: teamA,
      teamB: teamB
    )
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
    let periods = try GamePeriod
      .order { ($0.gameID, $0.position, $0.id) }
      .fetchAll(db)
    let teams = try Team.fetchAll(db)

    let goalsByGame = Dictionary(grouping: goals, by: \.gameID)
    let periodsByGame = Dictionary(grouping: periods, by: \.gameID)
    let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

    return Value(
      games: games.compactMap { game in
        guard
          let teamA = teamsByID[game.teamAID],
          let teamB = teamsByID[game.teamBID]
        else { return nil }

        let gameGoals = goalsByGame[game.id, default: []]
        let gamePeriods = periodsByGame[game.id, default: []]
        let phases = gamePhases(for: gamePeriods)
        guard !phases.isEmpty else { return nil }
        let currentPhase = phases[
          min(max(game.currentPhaseIndex, 0), phases.count - 1)
        ]
        return GameListItem(
          currentQuarter: currentPhase.periodNumber,
          endedAt: game.endedAt,
          id: game.id,
          periods: gamePeriods,
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
        goalTimeline: timeline,
        id: snapshot.game.id,
        location: snapshot.game.location,
        periods: snapshot.periods,
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

  let periodsByID = Dictionary(
    uniqueKeysWithValues: snapshot.periods.map { ($0.id, $0) }
  )

  for goal in snapshot.goals {
    guard let period = periodsByID[goal.gamePeriodID] else { continue }
    let periodNumber = period.number
    let scoringTeamBibColorHex: String
    let scoringTeamName: String
    let scoringTeamSide: GoalTimelineTeamSide

    if goal.teamID == snapshot.teamA.id {
      teamAScore += goal.points
      quarterScoresByPeriod[periodNumber, default: (0, 0)].teamA += goal.points
      scoringTeamBibColorHex = snapshot.game.teamABibColorHex
      scoringTeamName = snapshot.teamA.name
      scoringTeamSide = .teamA
    } else if goal.teamID == snapshot.teamB.id {
      teamBScore += goal.points
      quarterScoresByPeriod[periodNumber, default: (0, 0)].teamB += goal.points
      scoringTeamBibColorHex = snapshot.game.teamBBibColorHex
      scoringTeamName = snapshot.teamB.name
      scoringTeamSide = .teamB
    } else {
      scoringTeamBibColorHex = TeamColorPalette.blue
      scoringTeamName = "Unknown team"
      scoringTeamSide = .unknown
    }

    goalsByPeriod[periodNumber, default: []].append(
      GoalTimelineItem(
        clockSecondsRemaining: max(
          period.durationSeconds - goal.elapsedSeconds,
          0
        ),
        id: goal.id,
        period: periodNumber,
        points: goal.points,
        scoringTeamBibColorHex: scoringTeamBibColorHex,
        scoringTeamName: scoringTeamName,
        scoringTeamSide: scoringTeamSide,
        teamAScore: teamAScore,
        teamBScore: teamBScore
      )
    )
  }

  let maximumPeriod = snapshot.periods.count
  let playedPeriod = snapshot.game.endedAt == nil
    ? min(
      max(
        snapshot.currentPhase.periodNumber,
        snapshot.goals.compactMap { periodsByID[$0.gamePeriodID]?.number }.max() ?? 1
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
  var previousGoalElapsedSecondsByPeriod: [GamePeriod.ID: Int] = [:]

  for goal in goals {
    let previousElapsedSeconds = previousGoalElapsedSecondsByPeriod[
      goal.gamePeriodID,
      default: 0
    ]
    let duration = max(goal.elapsedSeconds - previousElapsedSeconds, 0)
    previousGoalElapsedSecondsByPeriod[goal.gamePeriodID] = goal.elapsedSeconds

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
  periods: [GamePeriod]
) -> String {
  let orderedPeriods = periods.sorted { $0.position < $1.position }
  guard let firstPeriod = orderedPeriods.first else { return "No periods" }
  let periodDurations = orderedPeriods.map(\.durationSeconds)
  let periodSummary = Set(periodDurations).count == 1
    ? "\(orderedPeriods.count) × \(formattedDuration(firstPeriod.durationSeconds))"
    : periodDurations.map(formattedDuration).joined(separator: " / ")
  let breaks = orderedPeriods.compactMap(\.breakAfterDurationSeconds)
    .map(formattedDuration)
  guard !breaks.isEmpty else { return periodSummary }
  if Set(breaks).count == 1, let first = breaks.first {
    return "\(periodSummary) · \(first) breaks"
  }
  return "\(periodSummary) · breaks \(breaks.joined(separator: " / "))"
}

private nonisolated func formattedDuration(_ seconds: Int) -> String {
  let clampedSeconds = max(seconds, 0)
  return "\(clampedSeconds / 60):\(String(format: "%02d", clampedSeconds % 60))"
}

private nonisolated enum GameQueryError: Error {
  case gameNotFound
  case periodsNotFound
  case teamNotFound
}
