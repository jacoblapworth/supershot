import Dependencies
import Foundation
import SQLiteData

nonisolated struct GameTimerUpdate: Equatable, Sendable {
  var alarmAuthorizationDenied = false
  var snapshot: GameSnapshot
}

nonisolated struct GameTimerClient: Sendable {
  var cancelAlert: @Sendable (Game.ID) async -> Void
  var endPresentation: @Sendable (Game.ID) async -> Void
  var pause: @Sendable (Game.ID, Int?) async throws -> GameSnapshot
  var reconcile: @Sendable (Game.ID) async throws -> GameSnapshot
  var refreshActivity: @Sendable (Game.ID) async -> Void
  var scheduleAlert: @Sendable (Game.ID) async -> Void
  var startOrResume: @Sendable (Game.ID, Int?, Bool) async throws -> GameTimerUpdate
}

nonisolated struct GameTimerSystemClient: Sendable {
  var cancelAlarm: @Sendable (Game.ID) async -> Void
  var endActivity: @Sendable (Game.ID) async -> Void
  var scheduleAlarm: @Sendable (GameSnapshot, Bool) async -> Bool
  var updateActivity: @Sendable (GameSnapshot, Bool) async -> Void
}

extension DependencyValues {
  nonisolated var gameTimer: GameTimerClient {
    get { self[GameTimerClientKey.self] }
    set { self[GameTimerClientKey.self] = newValue }
  }

  nonisolated var gameTimerSystem: GameTimerSystemClient {
    get { self[GameTimerSystemClientKey.self] }
    set { self[GameTimerSystemClientKey.self] = newValue }
  }
}

private nonisolated enum GameTimerClientKey: DependencyKey {
  static var liveValue: GameTimerClient {
    @Dependency(\.gameTimerSystem) var system
    return GameTimerClient.live(system: system)
  }

  static var previewValue: GameTimerClient {
    GameTimerClient.live(system: .noop)
  }

  static var testValue: GameTimerClient {
    GameTimerClient.live(system: .noop)
  }
}

private nonisolated enum GameTimerSystemClientKey: DependencyKey {
  static var liveValue: GameTimerSystemClient {
    .live
  }

  static var previewValue: GameTimerSystemClient {
    .noop
  }

  static var testValue: GameTimerSystemClient {
    .noop
  }
}

nonisolated extension GameTimerSystemClient {
  static let noop = Self(
    cancelAlarm: { _ in },
    endActivity: { _ in },
    scheduleAlarm: { _, _ in false },
    updateActivity: { _, _ in }
  )
}

nonisolated extension GameTimerClient {
  static func live(system: GameTimerSystemClient) -> Self {
    Self(
      cancelAlert: { gameID in
        await system.cancelAlarm(gameID)
      },
      endPresentation: { gameID in
        await system.cancelAlarm(gameID)
        await system.endActivity(gameID)
      },
      pause: { gameID, expectedPeriod in
        @Dependency(\.date) var date
        @Dependency(\.defaultDatabase) var database
        let now = date.now
        let (didPause, snapshot) = try await database.write { db in
          guard var game = try Game.find(gameID).fetchOne(db) else {
            throw GameTimerError.gameNotFound
          }
          game = reconciledGame(game, now: now)
          guard
            game.endedAt == nil,
            expectedPeriod == nil || expectedPeriod == game.currentPeriod
          else {
            return (false, try snapshot(db, replacing: game))
          }

          if game.timerEndsAt != nil {
            game.elapsedSeconds = GameTimerMath.elapsedSeconds(
              durationSeconds: game.currentTimerDurationSeconds,
              persistedElapsedSeconds: game.elapsedSeconds,
              timerEndsAt: game.timerEndsAt,
              now: now
            )
            game.timerEndsAt = nil
            try persistTimerState(game, in: db)
            return (true, try snapshot(db, replacing: game))
          }
          return (false, try snapshot(db, replacing: game))
        }
        if didPause {
          await system.cancelAlarm(gameID)
        }
        await system.updateActivity(snapshot, true)
        return snapshot
      },
      reconcile: { gameID in
        @Dependency(\.date) var date
        @Dependency(\.defaultDatabase) var database
        let now = date.now
        let snapshot = try await database.write { db in
          guard let storedGame = try Game.find(gameID).fetchOne(db) else {
            throw GameTimerError.gameNotFound
          }
          let game = reconciledGame(storedGame, now: now)
          if shouldPersistReconciliation(from: storedGame, to: game, now: now) {
            try persistTimerState(game, in: db)
          }
          return try snapshot(db, replacing: game)
        }
        await system.updateActivity(snapshot, true)
        return snapshot
      },
      refreshActivity: { gameID in
        @Dependency(\.defaultDatabase) var database
        guard
          let snapshot = try? await database.read({ db in
            try GameSnapshot.fetch(db, gameID: gameID)
          })
        else { return }
        await system.updateActivity(snapshot, true)
      },
      scheduleAlert: { gameID in
        @Dependency(\.defaultDatabase) var database
        guard
          let snapshot = try? await database.read({ db in
            try GameSnapshot.fetch(db, gameID: gameID)
          }),
          snapshot.game.timerEndsAt != nil
        else { return }
        _ = await system.scheduleAlarm(snapshot, false)
      },
      startOrResume: { gameID, expectedPeriod, requestsAuthorization in
        @Dependency(\.date) var date
        @Dependency(\.defaultDatabase) var database
        let now = date.now
        let (didStart, snapshot) = try await database.write { db in
          guard var game = try Game.find(gameID).fetchOne(db) else {
            throw GameTimerError.gameNotFound
          }
          game = reconciledGame(game, now: now)
          guard
            game.endedAt == nil,
            expectedPeriod == nil || expectedPeriod == game.currentPeriod,
            game.elapsedSeconds < game.currentTimerDurationSeconds
          else {
            return (false, try snapshot(db, replacing: game))
          }

          guard game.timerEndsAt == nil else {
            return (false, try snapshot(db, replacing: game))
          }
          game.hasTimerStartedCurrentPeriod = true
          game.timerEndsAt = GameTimerMath.endDate(
            durationSeconds: game.currentTimerDurationSeconds,
            elapsedSeconds: game.elapsedSeconds,
            now: now
          )
          try persistTimerState(game, in: db)
          return (game.timerEndsAt != nil, try snapshot(db, replacing: game))
        }

        await system.updateActivity(snapshot, true)
        let alarmAuthorizationDenied = didStart
          ? await system.scheduleAlarm(snapshot, requestsAuthorization)
          : false
        return GameTimerUpdate(
          alarmAuthorizationDenied: alarmAuthorizationDenied,
          snapshot: snapshot
        )
      }
    )
  }
}

nonisolated extension Game {
  var currentTimerDurationSeconds: Int {
    Swift.max(isInBreak ? breakDuration(after: currentPeriod) : periodDurationSeconds, 0)
  }
}

private nonisolated func reconciledGame(_ storedGame: Game, now: Date) -> Game {
  var game = storedGame
  game.elapsedSeconds = GameTimerMath.elapsedSeconds(
    durationSeconds: game.currentTimerDurationSeconds,
    persistedElapsedSeconds: game.elapsedSeconds,
    timerEndsAt: game.timerEndsAt,
    now: now
  )

  guard
    let timerEndsAt = game.timerEndsAt,
    timerEndsAt <= now
  else { return game }

  game.elapsedSeconds = game.currentTimerDurationSeconds
  game.timerEndsAt = nil

  guard !game.isInBreak, game.currentPeriod < ScoringFeature.State.maximumPeriod else {
    return game
  }

  game.isAwaitingCentrePassConfirmation = true
  let breakDurationSeconds = max(game.breakDuration(after: game.currentPeriod), 0)
  guard breakDurationSeconds > 0 else { return game }

  let breakEndsAt = timerEndsAt.addingTimeInterval(TimeInterval(breakDurationSeconds))
  game.isInBreak = true
  game.elapsedSeconds = GameTimerMath.elapsedSeconds(
    durationSeconds: breakDurationSeconds,
    persistedElapsedSeconds: 0,
    timerEndsAt: breakEndsAt,
    now: now
  )
  game.timerEndsAt = breakEndsAt > now ? breakEndsAt : nil
  return game
}

private nonisolated func shouldPersistReconciliation(
  from storedGame: Game,
  to game: Game,
  now: Date
) -> Bool {
  guard storedGame != game else { return false }
  guard let timerEndsAt = storedGame.timerEndsAt else { return false }
  return timerEndsAt <= now
}

private nonisolated func persistTimerState(_ game: Game, in db: Database) throws {
  try Game.find(game.id).update {
    $0.currentPeriod = game.currentPeriod
    $0.elapsedSeconds = game.elapsedSeconds
    $0.hasTimerStartedCurrentPeriod = game.hasTimerStartedCurrentPeriod
    $0.isAwaitingCentrePassConfirmation = game.isAwaitingCentrePassConfirmation
    $0.isInBreak = game.isInBreak
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
    teamA: snapshot.teamA,
    teamB: snapshot.teamB
  )
}

private nonisolated enum GameTimerError: Error {
  case gameNotFound
}
