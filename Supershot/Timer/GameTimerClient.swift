import Dependencies
import Foundation
import SQLiteData

nonisolated struct GameTimerUpdate: Equatable, Sendable {
  var alarmSchedulingFailed = false
  var snapshot: GameSnapshot
}

/// For managing game alarms and live activities
nonisolated struct GameTimerClient: Sendable {
  var cancelAlarm: @Sendable (Game.ID) async -> Void
  var endPresentation: @Sendable (Game.ID) async -> Void
  var pause: @Sendable (Game.ID, Int?) async throws -> GameSnapshot
  var reconcile: @Sendable (Game.ID) async throws -> GameSnapshot
  var refreshActivity: @Sendable (Game.ID) async -> Void
  /// Returns true when scheduling fails after authorization.
  var scheduleAlarm: @Sendable (Game.ID) async -> Bool
  /// Skip to end of the game timer
  var skip: @Sendable (Game.ID, Int?) async throws -> GameSnapshot
  var startOrResume: @Sendable (Game.ID, Int?) async throws -> GameTimerUpdate
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
          let timeline = storedSnapshot.timeline
          var game = reconciledGame(storedGame, timeline: timeline, now: now)
          guard
            game.endedAt == nil,
            expectedPhaseIndex == nil || expectedPhaseIndex == game.currentPhaseIndex
          else {
            if storedGame != game { try persistTimerState(game, in: db) }
            return (false, try snapshot(db, replacing: game))
          }

          guard game.timerEndsAt != nil else {
            if storedGame != game { try persistTimerState(game, in: db) }
            return (false, try snapshot(db, replacing: game))
          }
          game.elapsedSeconds = GameTimerClient.elapsedSeconds(
            durationSeconds: timeline.phase(at: game.currentPhaseIndex)!.durationSeconds,
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
            timeline: storedSnapshot.timeline,
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
        else { return false }
        if await hasActiveProAccess(proSubscription) {
          return await alarms.scheduleAlarm(snapshot)
        } else {
          await endPremiumPresentation(alarms: alarms, snapshot: snapshot)
          return false
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
          let timeline = storedSnapshot.timeline
          var game = reconciledGame(storedGame, timeline: timeline, now: now)
          guard
            game.endedAt == nil,
            expectedPhaseIndex == nil || expectedPhaseIndex == game.currentPhaseIndex,
            !game.progress.isFinalPeriodComplete(in: timeline)
          else {
            if storedGame != game { try persistTimerState(game, in: db) }
            return (false, try snapshot(db, replacing: game))
          }

          game.elapsedSeconds = timeline.phase(at: game.currentPhaseIndex)!.durationSeconds
          game.timerEndsAt = nil
          game.progress.complete(in: timeline, boundary: now)
          try persistTimerState(game, in: db)
          return (true, try snapshot(db, replacing: game))
        }
        if await hasActiveProAccess(proSubscription) {
          if didSkip {
            await alarms.cancelAlarm(gameID, snapshot.phases.count)
            if snapshot.game.timerEndsAt != nil {
              _ = await alarms.scheduleAlarm(snapshot)
            }
          }
          await alarms.updateActivity(snapshot, true)
        } else {
          await endPremiumPresentation(alarms: alarms, snapshot: snapshot)
        }
        return snapshot
      },
      startOrResume: { gameID, expectedPhaseIndex in
        @Dependency(\.alarmClient) var alarms
        @Dependency(\.date) var date
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.proSubscription) var proSubscription
        
        let now = date.now
        let (didStart, snapshot) = try await database.write { db in
          let storedSnapshot = try GameSnapshot.fetch(db, gameID: gameID)
          let storedGame = storedSnapshot.game
          let timeline = storedSnapshot.timeline
          var game = reconciledGame(storedGame, timeline: timeline, now: now)
          let phase = timeline.phase(at: game.currentPhaseIndex)!
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

          if phase.isPlayingPeriod { game.lateScoringPeriodNumber = nil }
          game.timerEndsAt = GameTimerClient.endDate(
            durationSeconds: phase.durationSeconds,
            elapsedSeconds: game.elapsedSeconds,
            now: now
          )
          try persistTimerState(game, in: db)
          return (game.timerEndsAt != nil, try snapshot(db, replacing: game))
        }

        let alarmSchedulingFailed: Bool
        if await hasActiveProAccess(proSubscription) {
          await alarms.updateActivity(snapshot, true)
          alarmSchedulingFailed = didStart
            ? await alarms.scheduleAlarm(snapshot)
            : false
        } else {
          await endPremiumPresentation(alarms: alarms, snapshot: snapshot)
          alarmSchedulingFailed = false
        }
        return GameTimerUpdate(
          alarmSchedulingFailed: alarmSchedulingFailed,
          snapshot: snapshot
        )
      }
    )
  }
}

private nonisolated func hasActiveProAccess(
  _ proSubscription: SubscriptionClient
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
    return GameTimeline(periods: periods)?.phases.count ?? 0
  }) ?? 0
}

nonisolated func reconciledGame(_ storedGame: Game, timeline: GameTimeline, now: Date) -> Game {
  guard storedGame.endedAt == nil else { return storedGame }
  var game = storedGame
  game.progress.reconcile(in: timeline, now: now)
  return game
}

private nonisolated func persistTimerState(_ game: Game, in db: Database) throws {
  try Game.find(game.id).update {
    $0.lateScoringPeriodNumber = #bind(game.lateScoringPeriodNumber)
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
    GameCountdown(elapsedSeconds: persistedElapsedSeconds, endsAt: timerEndsAt)
      .projection(durationSeconds: durationSeconds, now: now).elapsedSeconds
  }
  
  static nonisolated func endDate(
    durationSeconds: Int,
    elapsedSeconds: Int,
    now: Date
  ) -> Date? {
    GameCountdown(elapsedSeconds: elapsedSeconds).endDate(durationSeconds: durationSeconds, now: now)
  }
}
