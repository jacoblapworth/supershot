import Dependencies
import Foundation
import SQLiteData

nonisolated struct GameTimerUpdate: Equatable, Sendable {
  var alarmAuthorizationDenied = false
  var snapshot: GameSnapshot
}

/// For managing game alarms and live activities
nonisolated struct GameTimerClient: Sendable {
  var cancelAlarm: @Sendable (Game.ID) async -> Void
  var endPresentation: @Sendable (Game.ID) async -> Void
  var pause: @Sendable (Game.ID, Int?) async throws -> GameSnapshot
  var reconcile: @Sendable (Game.ID) async throws -> GameSnapshot
  var refreshActivity: @Sendable (Game.ID) async -> Void
  var scheduleAlarm: @Sendable (Game.ID) async -> Void
  /// Skip to end of the game timer
  var skip: @Sendable (Game.ID, Int?) async throws -> GameSnapshot
  var startOrResume: @Sendable (Game.ID, Int?, Bool) async throws -> GameTimerUpdate
}

extension DependencyValues {
  nonisolated var gameTimer: GameTimerClient {
    get { self[GameTimerClientKey.self] }
    set { self[GameTimerClientKey.self] = newValue }
  }
}

private nonisolated enum GameTimerClientKey: DependencyKey {
  static var liveValue: GameTimerClient {
    @Dependency(\.alarmClient) var alarmClient
    @Dependency(\.proSubscription) var proSubscription
    return GameTimerClient.live
  }

  static var previewValue: GameTimerClient {
    GameTimerClient.live
  }

  static var testValue: GameTimerClient {
    GameTimerClient.live
  }
}



nonisolated extension GameTimerClient {
  static var live: Self {
    Self(
      cancelAlarm: { gameID in
        @Dependency(\.alarmClient) var alarms
        await alarms.cancelAlarm(gameID, await phaseCount(for: gameID))
      },
      endPresentation: { gameID in
        @Dependency(\.alarmClient) var alarms
        await alarms.cancelAlarm(gameID, await phaseCount(for: gameID))
        await alarms.endActivity(gameID)
      },
      pause: { gameID, expectedPhaseIndex in
        @Dependency(\.date) var date
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.alarmClient) var alarms
        @Dependency(\.proSubscription) var proSubscription
        
        let now = date.now
        let (didPause, snapshot) = try await database.write { db in
          let storedSnapshot = try GameSnapshot.fetch(db, gameID: gameID)
          let storedGame = storedSnapshot.game
          let phases = storedSnapshot.phases
          var game = reconciledGame(storedGame, phases: phases, now: now)
          guard
            game.endedAt == nil,
            expectedPhaseIndex == nil || expectedPhaseIndex == game.currentPhaseIndex
          else {
            if storedGame != game { try persistTimerState(game, in: db) }
            return (false, try snapshot(db, replacing: game))
          }

          guard game.timerEndsAt != nil else {
            return (false, try snapshot(db, replacing: game))
          }
          game.elapsedSeconds = GameTimerClient.elapsedSeconds(
            durationSeconds: currentPhase(game, in: phases).durationSeconds,
            persistedElapsedSeconds: game.elapsedSeconds,
            timerEndsAt: game.timerEndsAt,
            now: now
          )
          game.timerEndsAt = nil
          try persistTimerState(game, in: db)
          return (true, try snapshot(db, replacing: game))
        }
        
        if await hasActiveProAccess(proSubscription) {
          if didPause { await alarms.cancelAlarm(gameID, snapshot.phases.count) }
          await alarms.updateActivity(snapshot, true)
        } else {
          await endPremiumPresentation(alarms: alarms, snapshot: snapshot)
        }
        return snapshot
      },
      reconcile: { gameID in
        @Dependency(\.alarmClient) var alarms
        @Dependency(\.date.now) var now
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.proSubscription) var proSubscription

        let snapshot = try await database.write { db in
          let storedSnapshot = try GameSnapshot.fetch(db, gameID: gameID)
          let storedGame = storedSnapshot.game
          let game = reconciledGame(
            storedGame,
            phases: storedSnapshot.phases,
            now: now
          )
          if storedGame != game {
            try persistTimerState(game, in: db)
          }
          return try snapshot(db, replacing: game)
        }
        if await hasActiveProAccess(proSubscription) {
          await alarms.updateActivity(snapshot, true)
        } else {
          await endPremiumPresentation(alarms: alarms, snapshot: snapshot)
        }
        return snapshot
      },
      refreshActivity: { gameID in
        @Dependency(\.alarmClient) var alarms
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.proSubscription) var proSubscription
        
        guard
          let snapshot = try? await database.read({ db in
            try GameSnapshot.fetch(db, gameID: gameID)
          })
        else { return }
        if await hasActiveProAccess(proSubscription) {
          await alarms.updateActivity(snapshot, true)
        } else {
          await endPremiumPresentation(alarms: alarms, snapshot: snapshot)
        }
      },
      scheduleAlarm: { gameID in
        @Dependency(\.alarmClient) var alarms
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.proSubscription) var proSubscription
        
        guard let snapshot = try? await database.read({ db in
            try GameSnapshot.fetch(db, gameID: gameID)
          }),
          snapshot.game.timerEndsAt != nil
        else { return }
        if await hasActiveProAccess(proSubscription) {
          _ = await alarms.scheduleAlarm(snapshot, false)
        } else {
          await endPremiumPresentation(alarms: alarms, snapshot: snapshot)
        }
      },
      skip: { gameID, expectedPhaseIndex in
        @Dependency(\.alarmClient) var alarms
        @Dependency(\.date) var date
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.proSubscription) var proSubscription
        
        let now = date.now
        let (didSkip, snapshot) = try await database.write { db in
          let storedSnapshot = try GameSnapshot.fetch(db, gameID: gameID)
          let storedGame = storedSnapshot.game
          let phases = storedSnapshot.phases
          var game = reconciledGame(storedGame, phases: phases, now: now)
          guard
            game.endedAt == nil,
            expectedPhaseIndex == nil || expectedPhaseIndex == game.currentPhaseIndex,
            !isFinalPeriodComplete(game, phases: phases)
          else {
            if storedGame != game { try persistTimerState(game, in: db) }
            return (false, try snapshot(db, replacing: game))
          }

          game.elapsedSeconds = currentPhase(game, in: phases).durationSeconds
          game.timerEndsAt = nil
          advanceCompletedPhase(&game, phases: phases, boundary: now)
          try persistTimerState(game, in: db)
          return (true, try snapshot(db, replacing: game))
        }
        if await hasActiveProAccess(proSubscription) {
          if didSkip {
            await alarms.cancelAlarm(gameID, snapshot.phases.count)
            if snapshot.game.timerEndsAt != nil {
              _ = await alarms.scheduleAlarm(snapshot, false)
            }
          }
          await alarms.updateActivity(snapshot, true)
        } else {
          await endPremiumPresentation(alarms: alarms, snapshot: snapshot)
        }
        return snapshot
      },
      startOrResume: { gameID, expectedPhaseIndex, requestsAuthorization in
        @Dependency(\.alarmClient) var alarms
        @Dependency(\.date) var date
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.proSubscription) var proSubscription
        
        let now = date.now
        let (didStart, snapshot) = try await database.write { db in
          let storedSnapshot = try GameSnapshot.fetch(db, gameID: gameID)
          let storedGame = storedSnapshot.game
          let phases = storedSnapshot.phases
          var game = reconciledGame(storedGame, phases: phases, now: now)
          let phase = currentPhase(game, in: phases)
          guard
            game.endedAt == nil,
            expectedPhaseIndex == nil || expectedPhaseIndex == game.currentPhaseIndex,
            game.elapsedSeconds < phase.durationSeconds,
            phase.isBreak || !game.isAwaitingCentrePassConfirmation,
            game.timerEndsAt == nil
          else {
            if storedGame != game { try persistTimerState(game, in: db) }
            return (false, try snapshot(db, replacing: game))
          }

          game.timerEndsAt = GameTimerClient.endDate(
            durationSeconds: phase.durationSeconds,
            elapsedSeconds: game.elapsedSeconds,
            now: now
          )
          try persistTimerState(game, in: db)
          return (game.timerEndsAt != nil, try snapshot(db, replacing: game))
        }

        let alarmAuthorizationDenied: Bool
        if await hasActiveProAccess(proSubscription) {
          await alarms.updateActivity(snapshot, true)
          alarmAuthorizationDenied = didStart
            ? await alarms.scheduleAlarm(snapshot, requestsAuthorization)
            : false
        } else {
          await endPremiumPresentation(alarms: alarms, snapshot: snapshot)
          alarmAuthorizationDenied = false
        }
        return GameTimerUpdate(
          alarmAuthorizationDenied: alarmAuthorizationDenied,
          snapshot: snapshot
        )
      }
    )
  }
}

private nonisolated func hasActiveProAccess(
  _ proSubscription: ProSubscriptionClient
) async -> Bool {
  (try? await proSubscription.currentAccess()) == .pro
}

private nonisolated func endPremiumPresentation(
  alarms: AlarmClient,
  snapshot: GameSnapshot
) async {
  await alarms.cancelAlarm(snapshot.game.id, snapshot.phases.count)
  await alarms.endActivity(snapshot.game.id)
}

private nonisolated func phaseCount(for gameID: Game.ID) async -> Int {
  @Dependency(\.defaultDatabase) var database
  return (try? await database.read { db in
    let periods = try GamePeriod
      .where { $0.gameID.eq(gameID) }
      .fetchAll(db)
    return gamePhases(for: periods).count
  }) ?? 0
}

/// Reconciles a persisted Game's timer-related state against the current time and advances phases as needed.
///
/// This function takes a snapshot of a stored `Game` and produces an updated copy that reflects
/// the passage of time up to `now`. It:
/// - Recomputes `elapsedSeconds` based on the current phase duration, previously persisted elapsed time,
///   and any active countdown (`timerEndsAt`), using `GameTimerClient.elapsedSeconds`.
/// - If the countdown has expired (i.e., `timerEndsAt` is in the past or equal to `now`), it repeatedly:
///   - Marks the current phase as complete by setting `elapsedSeconds` to the phase duration and clearing `timerEndsAt`.
///   - Advances the game to the next logical phase via `advanceCompletedPhase(_:boundary:)`, using the boundary time
///     at which the phase completed (the prior `timerEndsAt`).
///
/// The result is an in-memory `Game` value that accurately represents the game's timer progression as of `now`,
/// without persisting any changes. Callers are responsible for persisting the returned state if desired.
///
/// - Parameters:
///   - storedGame: The persisted `Game` value to reconcile. This value is not mutated.
///   - now: The current wall-clock time used for reconciliation.
/// - Returns: A new `Game` whose `elapsedSeconds`, `timerEndsAt`, and `currentPhaseIndex` are updated to reflect
///   the correct state at `now`, potentially having advanced through one or more completed phases.
/// - Important: This function is pure and does not perform any database I/O; persistence must be handled by the caller.
/// - SeeAlso: `GameTimerClient.elapsedSeconds(durationSeconds:persistedElapsedSeconds:timerEndsAt:now:)`,
///            `advanceCompletedPhase(_:boundary:)`
private nonisolated func reconciledGame(
  _ storedGame: Game,
  phases: [GamePhase],
  now: Date
) -> Game {
  var game = storedGame
  game.elapsedSeconds = GameTimerClient.elapsedSeconds(
    durationSeconds: currentPhase(game, in: phases).durationSeconds,
    persistedElapsedSeconds: game.elapsedSeconds,
    timerEndsAt: game.timerEndsAt,
    now: now
  )

  while let timerEndsAt = game.timerEndsAt, timerEndsAt <= now {
    game.elapsedSeconds = currentPhase(game, in: phases).durationSeconds
    game.timerEndsAt = nil
    advanceCompletedPhase(&game, phases: phases, boundary: timerEndsAt)
  }
  return game
}

private nonisolated func advanceCompletedPhase(
  _ game: inout Game,
  phases: [GamePhase],
  boundary: Date
) {
  switch currentPhase(game, in: phases) {
  case .period:
    guard game.currentPhaseIndex + 1 < phases.count else { return }
    game.isAwaitingCentrePassConfirmation = true
    game.currentPhaseIndex += 1
    game.elapsedSeconds = 0
    let duration = currentPhase(game, in: phases).durationSeconds
    if duration > 0 {
      game.timerEndsAt = boundary.addingTimeInterval(TimeInterval(duration))
    } else {
      advanceCompletedPhase(&game, phases: phases, boundary: boundary)
    }

  case .breakTime:
    game.currentPhaseIndex = Swift.min(
      game.currentPhaseIndex + 1,
      phases.count - 1
    )
    game.elapsedSeconds = 0
    game.timerEndsAt = nil
  }
}

private nonisolated func currentPhase(
  _ game: Game,
  in phases: [GamePhase]
) -> GamePhase {
  phases[Swift.min(Swift.max(game.currentPhaseIndex, 0), phases.count - 1)]
}

private nonisolated func isFinalPeriodComplete(
  _ game: Game,
  phases: [GamePhase]
) -> Bool {
  let phase = currentPhase(game, in: phases)
  return game.currentPhaseIndex == phases.count - 1
    && phase.isQuarter
    && game.elapsedSeconds >= phase.durationSeconds
    && game.timerEndsAt == nil
}

private nonisolated func persistTimerState(_ game: Game, in db: Database) throws {
  try Game.find(game.id).update {
    $0.currentPhaseIndex = game.currentPhaseIndex
    $0.elapsedSeconds = game.elapsedSeconds
    $0.isAwaitingCentrePassConfirmation = game.isAwaitingCentrePassConfirmation
    $0.timerEndsAt = #bind(game.timerEndsAt)
  }
  .execute(db)
}

private nonisolated func snapshot(
  _ db: Database,
  replacing game: Game
) throws -> GameSnapshot {
  let snapshot = try GameSnapshot.fetch(db, gameID: game.id)
  return GameSnapshot(
    game: game,
    goals: snapshot.goals,
    periods: snapshot.periods,
    teamA: snapshot.teamA,
    teamB: snapshot.teamB
  )
}

private nonisolated enum GameTimerError: Error {
  case gameNotFound
}

extension GameTimerClient {
  static nonisolated func elapsedSeconds(
    durationSeconds: Int,
    persistedElapsedSeconds: Int,
    timerEndsAt: Date?,
    now: Date
  ) -> Int {
    let durationSeconds = max(durationSeconds, 0)
    let persistedElapsedSeconds = min(
      max(persistedElapsedSeconds, 0),
      durationSeconds
    )
    guard let timerEndsAt else { return persistedElapsedSeconds }
    let remainingSeconds = min(
      max(Int(ceil(timerEndsAt.timeIntervalSince(now))), 0),
      durationSeconds
    )
    return durationSeconds - remainingSeconds
  }
  
  static nonisolated func endDate(
    durationSeconds: Int,
    elapsedSeconds: Int,
    now: Date
  ) -> Date? {
    let remainingSeconds = max(durationSeconds - elapsedSeconds, 0)
    guard remainingSeconds > 0 else { return nil }
    return now.addingTimeInterval(TimeInterval(remainingSeconds))
  }
}
