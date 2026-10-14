import Foundation
import SQLiteData
import SwiftUI

nonisolated struct GameListItem: Equatable, Identifiable, Sendable {
  var currentQuarter = 1
  let endedAt: Date?
  let id: Game.ID
  var periods: [GamePeriod] = []
  let startedAt: Date
  var teamABibColor: Color = ColorPalette.blue
  let teamAName: String
  let teamAScore: Int
  var teamBBibColor: Color = ColorPalette.red
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
  let color: Color
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
  var scoringTeamBibColor = ColorPalette.blue
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

/// The same analysis data is used for live and completed games.
nonisolated struct GameAnalysis: Equatable, Sendable {
  var goalTimeline = GoalTimeline()
  var periods: [GamePeriod] = []
  var statistics = CompletedGameStatistics()
  var teamABibColor = ColorPalette.blue
  var teamAName = ""
  var teamBBibColor = ColorPalette.red
  var teamBName = ""
}

nonisolated struct CompletedGameDetail: Equatable, Identifiable, Sendable {
  let endedAt: Date
  let goalTimeline: GoalTimeline
  let id: Game.ID
  var location: GameLocation?
  var periods: [GamePeriod] = []
  let startedAt: Date
  var statistics = CompletedGameStatistics()
  var teamABibColor = ColorPalette.blue
  let teamAName: String
  let teamAScore: Int
  var teamBBibColor = ColorPalette.red
  let teamBName: String
  let teamBScore: Int

  var analysis: GameAnalysis {
    GameAnalysis(
      goalTimeline: goalTimeline,
      periods: periods,
      statistics: statistics,
      teamABibColor: teamABibColor,
      teamAName: teamAName,
      teamBBibColor: teamBBibColor,
      teamBName: teamBName
    )
  }

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
/// participating `Team`s, all playing `GamePeriod`s with their break durations, and every
/// `Goal` that has been recorded for the game. From those inputs it derives
/// useful, read‑only facts such as the current phase, scoring period, whether the
/// final period has completed, and each team’s total score.
///
nonisolated struct GameSnapshot: Equatable, Sendable {
  let game: Game
  let goals: [Goal]
  let periods: [GamePeriod]
  let teamA: Team
  let teamB: Team

  var timeline: GameTimeline { GameTimeline(periods: periods)! }

  var phases: [GamePhase] { timeline.phases }

  var currentPhase: GamePhase { timeline.phase(at: game.currentPhaseIndex)! }

  var activePlayingPeriod: GamePeriod? {
    timeline.activePlayingPeriod(at: game.currentPhaseIndex)
  }

  var precedingPeriod: GamePeriod? {
    timeline.precedingPeriod(at: game.currentPhaseIndex)
  }

  var scoringContext: GameScoringContext? {
    GameScoringContext.resolve(
      phase: currentPhase, countdown: game.countdown,
      isAwaitingCentrePassConfirmation: game.isAwaitingCentrePassConfirmation,
      lateScoringPeriodNumber: game.lateScoringPeriodNumber
    )
  }

  var scoringPeriod: GamePeriod? {
    scoringContext.flatMap { timeline.scoringPeriod(for: $0) }
  }

  var isFinalPeriodComplete: Bool {
    game.progress.isFinalPeriodComplete(in: timeline)
  }

  var canUndoDuringConfirmation: Bool {
    game.scoring.canUndoDuringConfirmation(
      latestGoal: goals.max(by: { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }), periods: periods)
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
    guard
      let timeline = GameTimeline(periods: periods),
      timeline.phase(at: game.currentPhaseIndex) != nil
    else {
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
    return try fetch(db, games: games, goals: Goal.fetchAll(db))
  }

  fileprivate func fetch(_ db: Database, games: [Game], goals: [Goal]) throws -> Value {
    let gameIDs = games.map(\.id)
    let teamIDs = Set(games.flatMap { [$0.teamAID, $0.teamBID] })
    let periods = try GamePeriod
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
          teamABibColor: game.teamABibColor,
          teamAName: teamA.name,
          teamAScore: gameGoals
            .filter { $0.teamID == teamA.id }
            .reduce(0) { $0 + $1.points },
          teamBBibColor: game.teamBBibColor,
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
          color: team.color,
          gameCount: gameCounts[team.id, default: 0],
          id: team.id,
          name: team.name
        )
      }
    )
  }
}

nonisolated struct TeamStatistics: Equatable, Sendable {
  var wins = 0
  var losses = 0
  var draws = 0
  var pointsScored = 0
  var pointsAgainst = 0

  var gamesPlayed: Int { wins + losses + draws }
  var pointsDifference: Int { pointsScored - pointsAgainst }
  var winRate: Double? {
    gamesPlayed == 0 ? nil : Double(wins) / Double(gamesPlayed)
  }

  init(
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

  init(teamID: Team.ID, games: [Game], goals: [Goal]) {
    self.init()
    let goalsByGame = Dictionary(grouping: goals, by: \.gameID)
    for game in games where game.endedAt != nil
      && (game.teamAID == teamID || game.teamBID == teamID) {
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

nonisolated struct TeamDetailRequest: FetchKeyRequest {
  struct Value: Equatable, Sendable {
    var games: [GameListItem] = []
    var team: Team?
    var statistics = TeamStatistics()
  }

  let teamID: Team.ID

  func fetch(_ db: Database) throws -> Value {
    guard let team = try Team.find(teamID).fetchOne(db) else {
      return Value()
    }
    let games = try Game
      .where { $0.teamAID.eq(teamID) || $0.teamBID.eq(teamID) }
      .order { ($0.startedAt.desc(), $0.id.desc()) }
      .fetchAll(db)
    let gameIDs = games.map(\.id)
    let goals = try Goal.where { $0.gameID.in(gameIDs) }.fetchAll(db)
    return Value(
      games: try GamesRequest().fetch(db, games: games, goals: goals).games,
      team: team,
      statistics: TeamStatistics(teamID: teamID, games: games, goals: goals)
    )
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

nonisolated struct GameAnalysisRequest: FetchKeyRequest {
  struct Value: Equatable, Sendable {
    var analysis = GameAnalysis()
  }

  let gameID: Game.ID

  func fetch(_ db: Database) throws -> Value {
    let snapshot = try GameSnapshot.fetch(db, gameID: gameID)
    return Value(
      analysis: GameAnalysis(
        goalTimeline: goalTimeline(snapshot: snapshot),
        periods: snapshot.periods,
        statistics: completedGameStatistics(
          goals: snapshot.goals,
          teamAID: snapshot.teamA.id,
          teamBID: snapshot.teamB.id
        ),
        teamABibColor: snapshot.game.teamABibColor,
        teamAName: snapshot.teamA.name,
        teamBBibColor: snapshot.game.teamBBibColor,
        teamBName: snapshot.teamB.name
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
        teamABibColor: snapshot.game.teamABibColor,
        teamAName: snapshot.teamA.name,
        teamAScore: snapshot.teamAScore,
        teamBBibColor: snapshot.game.teamBBibColor,
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
    let scoringTeamBibColor: Color
    let scoringTeamName: String
    let scoringTeamSide: GoalTimelineTeamSide

    if goal.teamID == snapshot.teamA.id {
      teamAScore += goal.points
      quarterScoresByPeriod[periodNumber, default: (0, 0)].teamA += goal.points
      scoringTeamBibColor = snapshot.game.teamABibColor
      scoringTeamName = snapshot.teamA.name
      scoringTeamSide = .teamA
    } else if goal.teamID == snapshot.teamB.id {
      teamBScore += goal.points
      quarterScoresByPeriod[periodNumber, default: (0, 0)].teamB += goal.points
      scoringTeamBibColor = snapshot.game.teamBBibColor
      scoringTeamName = snapshot.teamB.name
      scoringTeamSide = .teamB
    } else {
      scoringTeamBibColor = ColorPalette.blue
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
        scoringTeamBibColor: scoringTeamBibColor,
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
        snapshot.currentPhase.associatedPeriod.number,
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
