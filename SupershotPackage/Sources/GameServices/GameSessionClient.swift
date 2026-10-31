import AlarmClient
import Database
import Dependencies
import Foundation
import GameCore
import IssueReporting
import SharedModels
import SQLiteData
import SubscriptionClient

public nonisolated enum GameSessionCommand: Equatable, Sendable {
  case reconcile
  case timing(GameTimingCommand, expectedPhaseIndex: Int?)
  case recordGoal(RecordGoalCommand)
  case undoGoal
  case selectCentrePass(Team.ID)
  case resolveCentrePass(completedPeriod: Int, taken: Bool)
  case finish
  case swapSides

  /// Sampling a clock for scoring validation must not mutate its persisted elapsed value.
  /// Undo and centre-pass commands intentionally do not advance the clock.
  public var reconcilesTiming: Bool {
    switch self {
    case .reconcile, .recordGoal, .finish: true
    case .timing(.setRemainingTime, _), .undoGoal, .selectCentrePass, .resolveCentrePass,
         .swapSides:
      false
    case .timing: true
    }
  }
}

public nonisolated enum GameSessionRejection: Error, Equatable, Sendable {
  case gameFinished
  case gameNotStarted
  case stalePhase
  case scoringUnavailable
  case confirmationRequired
  case invalidTeam
  case invalidCorrection
  case finishUnavailable
}

public nonisolated struct GameSessionUpdate: Equatable, Sendable {
  public enum Outcome: Equatable, Sendable {
    case applied
    case unchanged
    case rejected(GameSessionRejection)
  }

  public var outcome: Outcome
  public var snapshot: GameSnapshot

  public func acceptedSnapshot() throws -> GameSnapshot {
    if case let .rejected(reason) = outcome {
      throw reason
    }
    return snapshot
  }

  public init(outcome: Outcome, snapshot: GameSnapshot) {
    self.outcome = outcome
    self.snapshot = snapshot
  }
}

/// Authoritative application service. Each command reads, validates, and commits in
/// one transaction. Expected rejection is a value, so valid reconciliation can commit.
/// Only storage failures throw from the transaction; presentations happen afterwards.
public nonisolated struct GameSessionClient: Sendable {
  public var execute:
    @Sendable (Game.ID, GameSessionCommand, Date) async throws -> GameSessionUpdate

  public static var live: Self {
    Self(execute: { gameID, command, now in
      @Dependency(\.defaultDatabase) var database
      return try await database.write {
        try GameSessionTransaction.execute($0, gameID: gameID, command: command, now: now)
      }
    })
  }

  public static var unimplemented: Self {
    Self(execute: { _, _, _ in
      reportIssue("GameSessionClient.execute is unimplemented")
      throw GameSessionRejection.scoringUnavailable
    })
  }

  public init(execute:
    @escaping @Sendable (Game.ID, GameSessionCommand, Date) async throws -> GameSessionUpdate)
  {
    self.execute = execute
  }
}

public extension DependencyValues {
  nonisolated var gameSession: GameSessionClient {
    get { self[GameSessionClientKey.self] }
    set { self[GameSessionClientKey.self] = newValue }
  }
}

private nonisolated enum GameSessionClientKey: DependencyKey {
  static var liveValue: GameSessionClient {
    .live
  }

  static var testValue: GameSessionClient {
    .unimplemented
  }
}

package nonisolated enum GameSessionTransaction {
  package static func execute(
    _ db: Database,
    gameID: Game.ID,
    command: GameSessionCommand,
    now: Date
  ) throws -> GameSessionUpdate {
    let stored = try GameSnapshot.fetch(db, gameID: gameID)
    if stored.game.isPlanned {
      // An unstarted game can be prepared in scoring, but only its first clock can
      // start its lifecycle. Progression, goals, and finishing still require play.
      switch command {
      case .reconcile, .selectCentrePass, .swapSides,
           .timing(.setRemainingTime, _):
        break
      case .timing(.startOrResume, _) where stored.game.currentPhaseIndex == 0:
        break
      default:
        return GameSessionUpdate(outcome: .rejected(.gameNotStarted), snapshot: stored)
      }
    }
    var game = stored.game
    var outcome = GameSessionUpdate.Outcome.unchanged
    let commandDate: Date = if case let .recordGoal(goal) = command {
      goal.createdAt
    } else {
      now
    }

    if game.endedAt == nil, command.reconcilesTiming {
      let transitions = game.timing.reconcile(in: stored.timeline, now: commandDate)
      game.progress.apply(transitions)
      // Goal recording uses a sampled clock, but does not persist incidental tick progress.
      if case .recordGoal = command, transitions.isEmpty {
        game.timing = stored.game.timing
      }
    }

    if game.endedAt != nil {
      outcome = command == .reconcile ? .unchanged : .rejected(.gameFinished)
    } else {
      switch command {
      case .reconcile:
        outcome = game == stored.game ? .unchanged : .applied

      case let .timing(timingCommand, expectedPhaseIndex):
        let phase = stored.timeline.phase(at: game.currentPhaseIndex)!
        if expectedPhaseIndex != nil, expectedPhaseIndex != game.currentPhaseIndex {
          outcome = .rejected(.stalePhase)
        } else if game.isAwaitingCentrePassConfirmation,
                  timingCommand == .startOrResume, phase.isPlayingPeriod
        {
          outcome = .rejected(.confirmationRequired)
        } else if game.isAwaitingCentrePassConfirmation, case .setRemainingTime = timingCommand {
          outcome = .rejected(.invalidCorrection)
        } else {
          let result = game.timing.apply(
            timingCommand,
            in: stored.timeline,
            expectedPhaseIndex: expectedPhaseIndex,
            now: commandDate
          )
          game.progress.apply(result.transitions)
          if result.status == .applied, timingCommand == .startOrResume,
             game.startedAt == nil
          {
            game.startedAt = commandDate
          }
          switch result.status {
          case .applied: outcome = .applied
          case .unchanged: outcome = .unchanged
          case .rejected: outcome = .rejected(.invalidCorrection)
          }
        }

      case let .recordGoal(goalCommand):
        if goalCommand.gameID != gameID {
          outcome = .rejected(.scoringUnavailable)
        } else if goalCommand.teamID != stored.teamA.id && goalCommand.teamID != stored.teamB.id {
          outcome = .rejected(.invalidTeam)
        } else if goalCommand.expectedPhaseIndex != game.currentPhaseIndex {
          outcome = .rejected(.stalePhase)
        } else if let opportunity = scoringOpportunity(
          game: game,
          timeline: stored.timeline,
          requestedContext: goalCommand.scoringContext,
          now: commandDate
        ),
          goalCommand.source != .liveActivity || !opportunity.isLate
        {
          let goal = try game.scoring.recordGoal(
            goalCommand,
            opportunity: opportunity,
            teamAID: stored.teamA.id,
            teamBID: stored.teamB.id
          )
          try Goal.insert { goal }.execute(db)
          outcome = .applied
        } else {
          outcome = .rejected(.scoringUnavailable)
        }

      case .undoGoal:
        let latest = stored.goals.max { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        if game.isAwaitingCentrePassConfirmation,
           !game.scoring.canUndoDuringConfirmation(latestGoal: latest, periods: stored.periods)
        {
          outcome = .rejected(.confirmationRequired)
        } else if let latest {
          try Goal.find(latest.id).delete().execute(db)
          game.scoring.alternateCentrePass(teamAID: stored.teamA.id, teamBID: stored.teamB.id)
          outcome = .applied
        }

      case let .selectCentrePass(teamID):
        if teamID == stored.teamA.id || teamID == stored.teamB.id {
          game.centrePassTeamID = teamID
          outcome = game == stored.game ? .unchanged : .applied
        } else {
          outcome = .rejected(.invalidTeam)
        }

      case let .resolveCentrePass(completedPeriod, taken):
        if stored.timeline.precedingPeriod(at: game.currentPhaseIndex)?.number == completedPeriod {
          game.scoring.resolveCentrePass(
            taken: taken,
            teamAID: stored.teamA.id,
            teamBID: stored.teamB.id
          )
          outcome = game == stored.game ? .unchanged : .applied
        } else {
          outcome = .rejected(.stalePhase)
        }

      case .finish:
        if game.timing.isFinalPeriodComplete(in: stored.timeline),
           !game.isAwaitingCentrePassConfirmation
        {
          game.endedAt = commandDate
          game.timerEndsAt = nil
          outcome = .applied
        } else {
          outcome = .rejected(.finishUnavailable)
        }

      case .swapSides:
        game.swapSides.toggle()
        outcome = .applied
      }
    }

    if game != stored.game {
      try persist(game, in: db)
    }
    return try GameSessionUpdate(outcome: outcome, snapshot: GameSnapshot.fetch(db, gameID: gameID))
  }

  private static func scoringOpportunity(
    game: Game,
    timeline: GameTimeline,
    requestedContext: GameScoringContext?,
    now: Date
  ) -> ScoringOpportunity? {
    guard let phase = timeline.phase(at: game.currentPhaseIndex),
          let context = GameScoringContext.resolve(
            phase: phase,
            countdown: game.countdown,
            isAwaitingCentrePassConfirmation: game.isAwaitingCentrePassConfirmation,
            lateScoringPeriodNumber: game.lateScoringPeriodNumber,
            now: now
          ),
          context == (requestedContext ?? .livePeriod(number: phase.associatedPeriod.number)),
          let period = timeline.scoringPeriod(for: context)
    else { return nil }
    return ScoringOpportunity(
      period: period,
      context: context,
      elapsedSeconds: game.countdown.projection(durationSeconds: period.durationSeconds, now: now)
        .elapsedSeconds
    )
  }

  private static func persist(_ game: Game, in db: Database) throws {
    try Game.find(game.id).update {
      $0.centrePassTeamID = #bind(game.centrePassTeamID)
      $0.lateScoringPeriodNumber = #bind(game.lateScoringPeriodNumber)
      $0.isAwaitingCentrePassConfirmation = game.isAwaitingCentrePassConfirmation
      $0.startedAt = #bind(game.startedAt)
      $0.currentPhaseIndex = game.currentPhaseIndex
      $0.elapsedSeconds = game.elapsedSeconds
      $0.timerEndsAt = #bind(game.timerEndsAt)
      $0.endedAt = #bind(game.endedAt)
      $0.swapSides = game.swapSides
    }.execute(db)
  }
}
