import Foundation
import GameCore
import SharedModels
import SQLiteData

package nonisolated struct GameListItem: Equatable, Identifiable, Sendable {
  package var currentQuarter = 1
  package let endedAt: Date?
  package let id: Game.ID
  package var periods: [GamePeriod] = []
  package let startedAt: Date?
  package var createdAt: Date
  package var scheduledAt: Date?
  package var court: String?
  package var teamABibColorHex: String = "#007AFF"
  package let teamAName: String
  package let teamAScore: Int
  package var teamBBibColorHex: String = "#FF3B30"
  package let teamBName: String
  package let teamBScore: Int

  package var isPlanned: Bool {
    startedAt == nil && endedAt == nil
  }

  package var isInProgress: Bool {
    startedAt != nil && endedAt == nil
  }

  package var isCompleted: Bool {
    endedAt != nil
  }

  package var timingSummary: String {
    gameTimingSummary(periods: periods)
  }

  package init(
    currentQuarter: Int = 1, endedAt: Date? = nil, id: Game.ID, periods: [GamePeriod] = [],
    startedAt: Date?, teamABibColorHex: String = "#007AFF", teamAName: String, teamAScore: Int,
    teamBBibColorHex: String = "#FF3B30", teamBName: String, teamBScore: Int,
    createdAt: Date? = nil, scheduledAt: Date? = nil, court: String? = nil
  ) {
    self.currentQuarter = currentQuarter
    self.endedAt = endedAt
    self.id = id
    self.periods = periods
    self.createdAt = createdAt ?? startedAt ?? .distantPast
    self.scheduledAt = scheduledAt
    self.court = court
    self.startedAt = startedAt
    self.teamABibColorHex = teamABibColorHex
    self.teamAName = teamAName
    self.teamAScore = teamAScore
    self.teamBBibColorHex = teamBBibColorHex
    self.teamBName = teamBName
    self.teamBScore = teamBScore
  }
}

package nonisolated struct TeamListItem: Equatable, Identifiable, Sendable {
  package let colorHex: String
  package let gameCount: Int
  package let id: Team.ID
  package let name: String

  package init(colorHex: String, gameCount: Int, id: Team.ID, name: String) {
    self.colorHex = colorHex
    self.gameCount = gameCount
    self.id = id
    self.name = name
  }
}

package nonisolated struct GoalTimeline: Equatable, Sendable {
  package var quarters: [GoalTimelineQuarter] = []

  package static func empty(through period: Int) -> Self {
    let finalPeriod = max(period, 1)
    return Self(
      quarters: (1 ... finalPeriod).reversed().map {
        GoalTimelineQuarter(
          goals: [],
          period: $0,
          teamAQuarterScore: 0,
          teamBQuarterScore: 0
        )
      }
    )
  }

  package init(quarters: [GoalTimelineQuarter] = []) {
    self.quarters = quarters
  }
}

package nonisolated struct GoalTimelineQuarter: Equatable, Identifiable, Sendable {
  package var id: Int {
    period
  }

  package let goals: [GoalTimelineItem]
  package let period: Int
  package let teamAQuarterScore: Int
  package let teamBQuarterScore: Int

  package init(
    goals: [GoalTimelineItem], period: Int, teamAQuarterScore: Int, teamBQuarterScore: Int
  ) {
    self.goals = goals
    self.period = period
    self.teamAQuarterScore = teamAQuarterScore
    self.teamBQuarterScore = teamBQuarterScore
  }
}

package nonisolated enum GoalTimelineTeamSide: Equatable, Sendable {
  case teamA
  case teamB
  case unknown
}

package nonisolated struct GoalTimelineItem: Equatable, Identifiable, Sendable {
  package let clockSecondsRemaining: Int
  package let id: Goal.ID
  package let period: Int
  package let points: Int
  package var scoringTeamBibColorHex = "#007AFF"
  package let scoringTeamName: String
  package let scoringTeamSide: GoalTimelineTeamSide
  package let teamAScore: Int
  package let teamBScore: Int

  package init(
    clockSecondsRemaining: Int, id: Goal.ID, period: Int, points: Int,
    scoringTeamBibColorHex: String = "#007AFF", scoringTeamName: String,
    scoringTeamSide: GoalTimelineTeamSide, teamAScore: Int, teamBScore: Int
  ) {
    self.clockSecondsRemaining = clockSecondsRemaining
    self.id = id
    self.period = period
    self.points = points
    self.scoringTeamBibColorHex = scoringTeamBibColorHex
    self.scoringTeamName = scoringTeamName
    self.scoringTeamSide = scoringTeamSide
    self.teamAScore = teamAScore
    self.teamBScore = teamBScore
  }
}

package nonisolated struct CentrePassStatistics: Equatable, Sendable {
  package let conversions: Int
  package let inferredTurnovers: Int
  package let opportunities: Int

  package init(conversions: Int, inferredTurnovers: Int, opportunities: Int) {
    self.conversions = conversions
    self.inferredTurnovers = inferredTurnovers
    self.opportunities = opportunities
  }
}

package nonisolated struct TeamGameStatistics: Equatable, Sendable {
  package var averageTimeToGoalSeconds: Double?
  package var centrePass: CentrePassStatistics?
  package var biggestLead = 0
  package var longestScoringRun = 0

  package init(
    averageTimeToGoalSeconds: Double? = nil, centrePass: CentrePassStatistics? = nil,
    biggestLead: Int = 0, longestScoringRun: Int = 0
  ) {
    self.averageTimeToGoalSeconds = averageTimeToGoalSeconds
    self.centrePass = centrePass
    self.biggestLead = biggestLead
    self.longestScoringRun = longestScoringRun
  }
}

package nonisolated struct CompletedGameStatistics: Equatable, Sendable {
  package var teamA = TeamGameStatistics()
  package var teamB = TeamGameStatistics()

  package init(
    teamA: TeamGameStatistics = TeamGameStatistics(),
    teamB: TeamGameStatistics = TeamGameStatistics()
  ) {
    self.teamA = teamA
    self.teamB = teamB
  }
}

/// The same analysis data is used for live and completed games.
package nonisolated struct GameAnalysis: Equatable, Sendable {
  package var goalTimeline = GoalTimeline()
  package var isComplete = false
  package var periods: [GamePeriod] = []
  package var statistics = CompletedGameStatistics()
  package var statisticsByPeriod: [Int: CompletedGameStatistics] = [:]
  package var teamABibColorHex = "#007AFF"
  package var teamAName = ""
  package var teamBBibColorHex = "#FF3B30"
  package var teamBName = ""

  package init(
    goalTimeline: GoalTimeline = GoalTimeline(), isComplete: Bool = false,
    periods: [GamePeriod] = [],
    statistics: CompletedGameStatistics = CompletedGameStatistics(),
    statisticsByPeriod: [Int: CompletedGameStatistics] = [:],
    teamABibColorHex: String = "#007AFF", teamAName: String = "",
    teamBBibColorHex: String = "#FF3B30", teamBName: String = ""
  ) {
    self.goalTimeline = goalTimeline
    self.isComplete = isComplete
    self.periods = periods
    self.statistics = statistics
    self.statisticsByPeriod = statisticsByPeriod
    self.teamABibColorHex = teamABibColorHex
    self.teamAName = teamAName
    self.teamBBibColorHex = teamBBibColorHex
    self.teamBName = teamBName
  }
}

package nonisolated struct CompletedGameDetail: Equatable, Identifiable, Sendable {
  package let endedAt: Date
  package let goalTimeline: GoalTimeline
  package let id: Game.ID
  package var location: GameLocation?
  package var scheduledAt: Date?
  package var court: String?
  package var periods: [GamePeriod] = []
  package let startedAt: Date
  package var statistics = CompletedGameStatistics()
  package var statisticsByPeriod: [Int: CompletedGameStatistics] = [:]
  package var teamABibColorHex = "#007AFF"
  package let teamAName: String
  package let teamAScore: Int
  package var teamBBibColorHex = "#FF3B30"
  package let teamBName: String
  package let teamBScore: Int

  package var analysis: GameAnalysis {
    GameAnalysis(
      goalTimeline: goalTimeline,
      isComplete: true,
      periods: periods,
      statistics: statistics,
      statisticsByPeriod: statisticsByPeriod,
      teamABibColorHex: teamABibColorHex,
      teamAName: teamAName,
      teamBBibColorHex: teamBBibColorHex,
      teamBName: teamBName
    )
  }

  package var resultTitle: String {
    if teamAScore == teamBScore {
      "Draw"
    } else if teamAScore > teamBScore {
      "\(teamAName) win"
    } else {
      "\(teamBName) win"
    }
  }

  package var timingSummary: String {
    gameTimingSummary(periods: periods)
  }

  package init(
    endedAt: Date, goalTimeline: GoalTimeline, id: Game.ID, location: GameLocation? = nil,
    periods: [GamePeriod] = [], startedAt: Date,
    statistics: CompletedGameStatistics = CompletedGameStatistics(),
    statisticsByPeriod: [Int: CompletedGameStatistics] = [:],
    teamABibColorHex: String = "#007AFF", teamAName: String, teamAScore: Int,
    teamBBibColorHex: String = "#FF3B30", teamBName: String, teamBScore: Int,
    scheduledAt: Date? = nil, court: String? = nil
  ) {
    self.scheduledAt = scheduledAt
    self.court = court
    self.endedAt = endedAt
    self.goalTimeline = goalTimeline
    self.id = id
    self.location = location
    self.periods = periods
    self.startedAt = startedAt
    self.statistics = statistics
    self.statisticsByPeriod = statisticsByPeriod
    self.teamABibColorHex = teamABibColorHex
    self.teamAName = teamAName
    self.teamAScore = teamAScore
    self.teamBBibColorHex = teamBBibColorHex
    self.teamBName = teamBName
    self.teamBScore = teamBScore
  }
}

/// A nonisolated, immutable snapshot of all state needed to reason about a single game at a point in time.
///
/// GameSnapshot aggregates the core records for a game so that higher–level
/// queries, computed properties, and presentation logic can be performed without
/// repeatedly hitting the database. It bundles the `Game` row itself, the
/// participating `Team`s, all playing `GamePeriod`s with their break durations, and every
/// `Goal` that has been recorded for the game. From those inputs it derives
/// useful, read‑only facts such as the current phase, scoring period, whether the
/// final period has completed, and each team’s total score.
///
public nonisolated struct GameSnapshot: Equatable, Sendable {
  public let game: Game
  public let goals: [Goal]
  public let periods: [GamePeriod]
  public let teamA: Team
  public let teamB: Team

  public var timeline: GameTimeline {
    GameTimeline(periods: periods)!
  }

  public var phases: [GamePhase] {
    timeline.phases
  }

  public var currentPhase: GamePhase {
    timeline.phase(at: game.currentPhaseIndex)!
  }

  public var activePlayingPeriod: GamePeriod? {
    timeline.activePlayingPeriod(at: game.currentPhaseIndex)
  }

  public var precedingPeriod: GamePeriod? {
    timeline.precedingPeriod(at: game.currentPhaseIndex)
  }

  public var scoringContext: GameScoringContext? {
    guard !game.isPlanned else { return nil }
    return GameScoringContext.resolve(
      phase: currentPhase, countdown: game.countdown,
      isAwaitingCentrePassConfirmation: game.isAwaitingCentrePassConfirmation,
      lateScoringPeriodNumber: game.lateScoringPeriodNumber
    )
  }

  public var scoringPeriod: GamePeriod? {
    scoringContext.flatMap { timeline.scoringPeriod(for: $0) }
  }

  public var isFinalPeriodComplete: Bool {
    !game.isPlanned && game.progress.isFinalPeriodComplete(in: timeline)
  }

  public var canUndoDuringConfirmation: Bool {
    game.scoring.canUndoDuringConfirmation(
      latestGoal: goals.max(by: { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }), periods: periods
    )
  }

  public var teamAScore: Int {
    goals
      .filter { $0.teamID == teamA.id }
      .reduce(0) { $0 + $1.points }
  }

  public var teamBScore: Int {
    goals
      .filter { $0.teamID == teamB.id }
      .reduce(0) { $0 + $1.points }
  }

  public static func fetch(_ db: Database, gameID: Game.ID) throws -> Self {
    guard let game = try Game.find(gameID).fetchOne(db) else {
      throw GameQueryError.gameNotFound
    }
    guard
      let teamA = try Team.find(game.teamAID).fetchOne(db),
      let teamB = try Team.find(game.teamBID).fetchOne(db)
    else {
      throw GameQueryError.teamNotFound
    }

    let periods =
      try GamePeriod
        .where { $0.gameID.eq(gameID) }
        .order { ($0.position, $0.id) }
        .fetchAll(db)
    guard
      let timeline = GameTimeline(periods: periods),
      timeline.phase(at: game.currentPhaseIndex) != nil
    else {
      throw GameQueryError.periodsNotFound
    }

    let unsortedGoals =
      try Goal
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

  public init(game: Game, goals: [Goal], periods: [GamePeriod], teamA: Team, teamB: Team) {
    self.game = game
    self.goals = goals
    self.periods = periods
    self.teamA = teamA
    self.teamB = teamB
  }
}

package nonisolated struct GamesRequest: FetchKeyRequest {
  package struct Value: Equatable, Sendable {
    package var games: [GameListItem] = []

    package init(games: [GameListItem] = []) {
      self.games = games
    }
  }

  package func fetch(_ db: Database) throws -> Value {
    let games =
      try Game
        .order { games in (games.startedAt.desc(), games.id.desc()) }
        .fetchAll(db)
    return try fetch(db, games: games, goals: Goal.fetchAll(db))
  }

  fileprivate func fetch(_ db: Database, games: [Game], goals: [Goal]) throws -> Value {
    let gameIDs = games.map(\.id)
    let teamIDs = Set(games.flatMap { [$0.teamAID, $0.teamBID] })
    let periods =
      try GamePeriod
        .where { $0.gameID.in(gameIDs) }
        .order { ($0.gameID, $0.position, $0.id) }
        .fetchAll(db)
    let teams = try Team.find(Array(teamIDs)).fetchAll(db)

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
        guard let timeline = GameTimeline(periods: gamePeriods),
              let currentPhase = timeline.phase(at: game.currentPhaseIndex)
        else { return nil }
        return GameListItem(
          currentQuarter: currentPhase.associatedPeriod.number,
          endedAt: game.endedAt,
          id: game.id,
          periods: gamePeriods,
          startedAt: game.startedAt,
          teamABibColorHex: game.teamABibColorHex,
          teamAName: teamA.name,
          teamAScore:
          gameGoals
            .filter { $0.teamID == teamA.id }
            .reduce(0) { $0 + $1.points },
          teamBBibColorHex: game.teamBBibColorHex,
          teamBName: teamB.name,
          teamBScore:
          gameGoals
            .filter { $0.teamID == teamB.id }
            .reduce(0) { $0 + $1.points },
          createdAt: game.createdAt, scheduledAt: game.scheduledAt, court: game.court
        )
      }
    )
  }

  package init() {}
}

package nonisolated struct TeamsRequest: FetchKeyRequest {
  package struct Value: Equatable, Sendable {
    package var teams: [TeamListItem] = []

    package init(teams: [TeamListItem] = []) {
      self.teams = teams
    }
  }

  package func fetch(_ db: Database) throws -> Value {
    let games = try Game.fetchAll(db)
    let teams =
      try Team
        .order { ($0.name, $0.id) }
        .fetchAll(db)
    let gameCounts = games.filter { !$0.isPlanned }.reduce(into: [Team.ID: Int]()) { counts, game in
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

  package init() {}
}

package nonisolated struct TeamStatistics: Equatable, Sendable {
  package var wins = 0
  package var losses = 0
  package var draws = 0
  package var pointsScored = 0
  package var pointsAgainst = 0

  package var gamesPlayed: Int {
    wins + losses + draws
  }

  package var pointsDifference: Int {
    pointsScored - pointsAgainst
  }

  package var winRate: Double? {
    gamesPlayed == 0 ? nil : Double(wins) / Double(gamesPlayed)
  }

  package init(
    wins: Int = 0,
    losses: Int = 0,
    draws: Int = 0,
    pointsScored: Int = 0,
    pointsAgainst: Int = 0
  ) {
    self.wins = wins
    self.losses = losses
    self.draws = draws
    self.pointsScored = pointsScored
    self.pointsAgainst = pointsAgainst
  }

  package init(teamID: Team.ID, games: [Game], goals: [Goal]) {
    self.init()
    let goalsByGame = Dictionary(grouping: goals, by: \.gameID)
    for game in games
      where game.endedAt != nil
      && (game.teamAID == teamID || game.teamBID == teamID)
    {
      let opponentID = game.teamAID == teamID ? game.teamBID : game.teamAID
      var scored = 0
      var against = 0
      for goal in goalsByGame[game.id, default: []] {
        if goal.teamID == teamID {
          scored += goal.points
        } else if goal.teamID == opponentID {
          against += goal.points
        }
      }
      pointsScored += scored
      pointsAgainst += against
      if scored > against {
        wins += 1
      } else if scored < against {
        losses += 1
      } else {
        draws += 1
      }
    }
  }
}

package nonisolated struct TeamDetailRequest: FetchKeyRequest {
  package struct Value: Equatable, Sendable {
    package var games: [GameListItem] = []
    package var team: Team?
    package var statistics = TeamStatistics()

    package init(
      games: [GameListItem] = [], team: Team? = nil, statistics: TeamStatistics = TeamStatistics()
    ) {
      self.games = games
      self.team = team
      self.statistics = statistics
    }
  }

  package let teamID: Team.ID

  package func fetch(_ db: Database) throws -> Value {
    guard let team = try Team.find(teamID).fetchOne(db) else {
      return Value()
    }
    let games =
      try Game
        .where { $0.teamAID.eq(teamID) || $0.teamBID.eq(teamID) }
        .order { ($0.startedAt.desc(), $0.id.desc()) }
        .fetchAll(db)
    let gameIDs = games.map(\.id)
    let goals = try Goal.where { $0.gameID.in(gameIDs) }.fetchAll(db)
    return try Value(
      games: GamesRequest().fetch(db, games: games, goals: goals).games,
      team: team,
      statistics: TeamStatistics(teamID: teamID, games: games, goals: goals)
    )
  }

  package init(teamID: Team.ID) {
    self.teamID = teamID
  }
}

package nonisolated struct GoalTimelineRequest: FetchKeyRequest {
  package struct Value: Equatable, Sendable {
    package var timeline = GoalTimeline()

    package init(timeline: GoalTimeline = GoalTimeline()) {
      self.timeline = timeline
    }
  }

  package let gameID: Game.ID

  package func fetch(_ db: Database) throws -> Value {
    try Value(
      timeline: goalTimeline(
        snapshot: GameSnapshot.fetch(db, gameID: gameID)
      )
    )
  }

  package init(gameID: Game.ID) {
    self.gameID = gameID
  }
}

package nonisolated struct GameAnalysisRequest: FetchKeyRequest {
  package struct Value: Equatable, Sendable {
    package var analysis = GameAnalysis()

    package init(analysis: GameAnalysis = GameAnalysis()) {
      self.analysis = analysis
    }
  }

  package let gameID: Game.ID

  package func fetch(_ db: Database) throws -> Value {
    let snapshot = try GameSnapshot.fetch(db, gameID: gameID)
    return Value(
      analysis: GameAnalysis(
        goalTimeline: goalTimeline(snapshot: snapshot),
        isComplete: snapshot.game.endedAt != nil,
        periods: snapshot.periods,
        statistics: completedGameStatistics(
          goals: snapshot.goals,
          teamAID: snapshot.teamA.id,
          teamBID: snapshot.teamB.id
        ),
        statisticsByPeriod: statisticsByPeriod(snapshot: snapshot),
        teamABibColorHex: snapshot.game.teamABibColorHex,
        teamAName: snapshot.teamA.name,
        teamBBibColorHex: snapshot.game.teamBBibColorHex,
        teamBName: snapshot.teamB.name
      )
    )
  }

  package init(gameID: Game.ID) {
    self.gameID = gameID
  }
}

package nonisolated struct GameDetailRequest: FetchKeyRequest {
  package struct Value: Equatable, Sendable {
    package var detail: CompletedGameDetail?

    package init(detail: CompletedGameDetail? = nil) {
      self.detail = detail
    }
  }

  package let gameID: Game.ID

  package func fetch(_ db: Database) throws -> Value {
    let snapshot = try GameSnapshot.fetch(db, gameID: gameID)
    guard let endedAt = snapshot.game.endedAt, let startedAt = snapshot.game.startedAt
    else { return Value() }
    let timeline = goalTimeline(snapshot: snapshot)

    return Value(
      detail: CompletedGameDetail(
        endedAt: endedAt,
        goalTimeline: timeline,
        id: snapshot.game.id,
        location: snapshot.game.location,
        periods: snapshot.periods,
        startedAt: startedAt,
        statistics: completedGameStatistics(
          goals: snapshot.goals,
          teamAID: snapshot.teamA.id,
          teamBID: snapshot.teamB.id
        ),
        statisticsByPeriod: statisticsByPeriod(snapshot: snapshot),
        teamABibColorHex: snapshot.game.teamABibColorHex,
        teamAName: snapshot.teamA.name,
        teamAScore: snapshot.teamAScore,
        teamBBibColorHex: snapshot.game.teamBBibColorHex,
        teamBName: snapshot.teamB.name,
        teamBScore: snapshot.teamBScore,
        scheduledAt: snapshot.game.scheduledAt, court: snapshot.game.court
      )
    )
  }

  package init(gameID: Game.ID) {
    self.gameID = gameID
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
      scoringTeamBibColorHex = "#007AFF"
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
  let playedPeriod =
    snapshot.game.endedAt == nil
      ? min(
        max(
          snapshot.currentPhase.associatedPeriod.number,
          snapshot.goals.compactMap { periodsByID[$0.gamePeriodID]?.number }.max() ?? 1
        ),
        maximumPeriod
      )
      : maximumPeriod

  return GoalTimeline(
    quarters: (1 ... max(playedPeriod, 1)).reversed().map { period in
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

private nonisolated func statisticsByPeriod(
  snapshot: GameSnapshot
) -> [Int: CompletedGameStatistics] {
  Dictionary(
    uniqueKeysWithValues: snapshot.periods.map { period in
      (
        period.number,
        completedGameStatistics(
          goals: snapshot.goals.filter { $0.gamePeriodID == period.id },
          teamAID: snapshot.teamA.id,
          teamBID: snapshot.teamB.id
        )
      )
    }
  )
}

/// Goals must be supplied in GameSnapshot chronological order.
nonisolated func completedGameStatistics(
  goals: [Goal],
  teamAID: Team.ID,
  teamBID: Team.ID
) -> CompletedGameStatistics {
  var goalDurationsByTeamID: [Team.ID: [Int]] = [:]
  var scores: [Team.ID: Int] = [:]
  var biggestLeads: [Team.ID: Int] = [:]
  var longestRuns: [Team.ID: Int] = [:]
  var runTeamID: Team.ID?
  var runLength = 0
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
      scores[goal.teamID, default: 0] += goal.points
      biggestLeads[teamAID] = max(
        biggestLeads[teamAID, default: 0],
        scores[teamAID, default: 0] - scores[teamBID, default: 0]
      )
      biggestLeads[teamBID] = max(
        biggestLeads[teamBID, default: 0],
        scores[teamBID, default: 0] - scores[teamAID, default: 0]
      )
      runLength = runTeamID == goal.teamID ? runLength + 1 : 1
      runTeamID = goal.teamID
      longestRuns[goal.teamID] = max(longestRuns[goal.teamID, default: 0], runLength)
    } else {
      // An unidentified scorer cannot establish a consecutive run for either team.
      runTeamID = nil
      runLength = 0
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
      centrePass: centrePassStatistics(for: teamID),
      biggestLead: biggestLeads[teamID, default: 0],
      longestScoringRun: longestRuns[teamID, default: 0]
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
  let periodSummary =
    Set(periodDurations).count == 1
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
