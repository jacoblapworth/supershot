import Foundation
import SQLiteData

extension GameScoreSnapshot {
  nonisolated static func fetch(
    _ db: Database,
    gameID: Game.ID,
    teamAID: Team.ID,
    teamBID: Team.ID
  ) throws -> Self {
    let snapshot = try GameSnapshot.fetch(db, gameID: gameID)
    return Self(
      canUndo: !snapshot.goals.isEmpty,
      canUndoDuringConfirmation: snapshot.canUndoDuringConfirmation,
      centrePassTeamID: resolvedCentrePassTeamID(
        snapshot.game.centrePassTeamID,
        teamAID: teamAID, teamBID: teamBID),
      teamAScore: snapshot.teamAScore,
      teamBScore: snapshot.teamBScore
    )
  }
}

nonisolated enum ScoringPersistenceError: Error {
  case gameNotFound
  case goalUnavailable
}

nonisolated func resolvedCentrePassTeamID(
  _ teamID: Team.ID?,
  teamAID: Team.ID,
  teamBID: Team.ID
) -> Team.ID {
  GameScoringState(centrePassTeamID: teamID).centrePass(teamAID: teamAID, teamBID: teamBID)
}

nonisolated enum ScoringPersistence {
  static func resolveCentrePass(
    _ db: Database, gameID: Game.ID, completedPeriod: Int, wasLastCentrePassTaken: Bool
  ) throws -> LastCentrePassSnapshot {
    let snapshot = try GameSnapshot.fetch(db, gameID: gameID)
    let game = snapshot.game
    guard game.endedAt == nil, snapshot.precedingPeriod?.number == completedPeriod else {
      throw ScoringPersistenceError.goalUnavailable
    }
    var scoring = game.scoring
    // Read ownership inside the same write as the answer, so concurrent late goals are retained.
    scoring.resolveCentrePass(
      taken: wasLastCentrePassTaken,
      teamAID: snapshot.teamA.id, teamBID: snapshot.teamB.id)
    try Game.find(gameID).update {
      $0.centrePassTeamID = #bind(scoring.centrePassTeamID)
      $0.isAwaitingCentrePassConfirmation = false
    }.execute(db)
    return LastCentrePassSnapshot(
      centrePassTeamID: scoring.centrePass(teamAID: snapshot.teamA.id, teamBID: snapshot.teamB.id))
  }
  static func undo(_ db: Database, gameID: Game.ID) throws -> GameScoreSnapshot {
    let snapshot = try GameSnapshot.fetch(db, gameID: gameID)
    let teamAID = snapshot.teamA.id
    let teamBID = snapshot.teamB.id
    let game = snapshot.game
    guard game.endedAt == nil,
      !game.isAwaitingCentrePassConfirmation || snapshot.canUndoDuringConfirmation
    else { throw ScoringPersistenceError.goalUnavailable }
    let latestGoal =
      try Goal
      .where { $0.gameID.eq(gameID) }
      .order { ($0.createdAt.desc(), $0.id.desc()) }
      .fetchOne(db)

    if let latestGoal {
      try Goal.find(latestGoal.id).delete().execute(db)
      var scoring = game.scoring
      scoring.alternateCentrePass(teamAID: teamAID, teamBID: teamBID)
      try Game.find(gameID).update {
        $0.centrePassTeamID = #bind(scoring.centrePassTeamID)
      }
      .execute(db)
    }

    return try GameScoreSnapshot.fetch(
      db,
      gameID: gameID,
      teamAID: teamAID,
      teamBID: teamBID
    )
  }

  static func selectCentrePass(_ db: Database, gameID: Game.ID, teamID: Team.ID) throws -> Team.ID {
    guard try Game.find(gameID).fetchOne(db) != nil else {
      throw ScoringPersistenceError.gameNotFound
    }
    try Game.find(gameID).update {
      $0.centrePassTeamID = #bind(teamID)
    }
    .execute(db)
    return teamID
  }

  nonisolated static func insertGoal(
    _ db: Database,
    gameID: UUID,
    teamID: UUID,
    expectedPhaseIndex: Int,
    goalID: UUID,
    createdAt: Date,
    points: Int = 1,
    scoringContext requestedContext: GameScoringContext? = nil
  ) throws -> GameScoreSnapshot {
    let snapshot = try GameSnapshot.fetch(db, gameID: gameID)
    let game = reconciledGame(snapshot.game, timeline: snapshot.timeline, now: createdAt)
    let teamAID = snapshot.teamA.id
    let teamBID = snapshot.teamB.id
    // createdAt is the tap/recording time. A queued live tap is not silently converted to a late goal.
    guard
      game.endedAt == nil,
      teamID == teamAID || teamID == teamBID,
      game.currentPhaseIndex == expectedPhaseIndex,
      let phase = snapshot.timeline.phase(at: game.currentPhaseIndex),
      let context = GameScoringContext.resolve(
        phase: phase, countdown: game.countdown,
        isAwaitingCentrePassConfirmation: game.isAwaitingCentrePassConfirmation,
        lateScoringPeriodNumber: game.lateScoringPeriodNumber, now: createdAt),
      context == (requestedContext ?? .livePeriod(number: phase.associatedPeriod.number)),
      let targetPeriod = snapshot.timeline.scoringPeriod(for: context)
    else { throw ScoringPersistenceError.goalUnavailable }
    let elapsedSeconds =
      context.isLate
      ? targetPeriod.durationSeconds
      : game.countdown.projection(
        durationSeconds: targetPeriod.durationSeconds, now: createdAt
      ).elapsedSeconds

    var scoring = game.scoring
    let command = RecordGoalCommand(
      gameID: gameID, teamID: teamID,
      expectedPhaseIndex: expectedPhaseIndex, goalID: goalID, createdAt: createdAt,
      points: points, scoringContext: requestedContext)
    let goal = try scoring.recordGoal(
      command,
      opportunity: ScoringOpportunity(
        period: targetPeriod, context: context, elapsedSeconds: elapsedSeconds),
      teamAID: teamAID, teamBID: teamBID)
    try Goal.insert { goal }.execute(db)
    try Game.find(gameID).update {
      $0.centrePassTeamID = #bind(scoring.centrePassTeamID)
    }.execute(db)

    return try GameScoreSnapshot.fetch(
      db,
      gameID: gameID,
      teamAID: teamAID,
      teamBID: teamBID
    )
  }
}
