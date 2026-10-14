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
  var setRemainingTime: @Sendable (Game.ID, Int, Int) async throws -> GameSnapshot = { _, _, _ in
    throw GameTimerError.invalidCorrection
  }
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
        @Dependency(\.gameSession) var session
        @Dependency(\.alarmClient) var alarms
        @Dependency(\.proSubscription) var proSubscription
        
        let now = date.now
        let update = try await session.execute(gameID, .timing(.pause, expectedPhaseIndex: expectedPhaseIndex), now)
        let snapshot = update.snapshot
        let didPause = update.outcome == .applied
        
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
        @Dependency(\.gameSession) var session
        @Dependency(\.proSubscription) var proSubscription

        let update = try await session.execute(gameID, .reconcile, now)
        let snapshot = update.snapshot
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
        @Dependency(\.gameSession) var session
        @Dependency(\.proSubscription) var proSubscription
        
        let now = date.now
        let update = try await session.execute(gameID, .timing(.skip, expectedPhaseIndex: expectedPhaseIndex), now)
        let snapshot = update.snapshot
        let didSkip = update.outcome == .applied
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
      setRemainingTime: { gameID, expectedPhaseIndex, remainingSeconds in
        @Dependency(\.date.now) var now
        @Dependency(\.gameSession) var session
        @Dependency(\.alarmClient) var alarms
        @Dependency(\.proSubscription) var proSubscription
        let update = try await session.execute(gameID, .timing(.setRemainingTime(remainingSeconds), expectedPhaseIndex: expectedPhaseIndex), now)
        guard case .applied = update.outcome else { throw GameTimerError.invalidCorrection }
        let updated = update.snapshot
        await alarms.cancelAlarm(gameID, updated.phases.count)
        if await hasActiveProAccess(proSubscription) {
          await alarms.updateActivity(updated, true)
        } else {
          await alarms.endActivity(gameID)
        }
        return updated
      },
      startOrResume: { gameID, expectedPhaseIndex in
        @Dependency(\.alarmClient) var alarms
        @Dependency(\.date) var date
        @Dependency(\.gameSession) var session
        @Dependency(\.proSubscription) var proSubscription
        
        let now = date.now
        let update = try await session.execute(gameID, .timing(.startOrResume, expectedPhaseIndex: expectedPhaseIndex), now)
        let snapshot = update.snapshot
        let didStart = update.outcome == .applied

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

private nonisolated enum GameTimerError: Error, LocalizedError {
  case gameNotFound
  case invalidCorrection

  var errorDescription: String? {
    switch self {
    case .gameNotFound: "The game could not be found."
    case .invalidCorrection:
      "The clock has changed. Close the editor and pause the current clock before trying again."
    }
  }
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
