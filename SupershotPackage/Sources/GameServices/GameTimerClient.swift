import AlarmClient
import Database
import Dependencies
import Foundation
import GameCore
import IssueReporting
import SharedModels
import SubscriptionClient

nonisolated public struct GameTimerUpdate: Equatable, Sendable {
  public var alarmSchedulingFailed = false
  public var snapshot: GameSnapshot

  public init(alarmSchedulingFailed: Bool = false, snapshot: GameSnapshot) {
    self.alarmSchedulingFailed = alarmSchedulingFailed
    self.snapshot = snapshot
  }
}

/// UI and intent adapter for timing commands and post-commit presentation.
nonisolated public struct GameTimerClient: Sendable {
  public var cancelAlarm: @Sendable (Game.ID) async -> Void
  public var endPresentation: @Sendable (Game.ID) async -> Void
  public var pause: @Sendable (Game.ID, Int?) async throws -> GameSnapshot
  public var reconcile: @Sendable (Game.ID) async throws -> GameSnapshot
  public var refreshActivity: @Sendable (Game.ID) async -> Void
  /// Returns true when scheduling fails after authorization.
  public var scheduleAlarm: @Sendable (Game.ID) async -> Bool
  /// Skip to end of the game timer
  public var skip: @Sendable (Game.ID, Int?) async throws -> GameSnapshot
  public var setRemainingTime: @Sendable (Game.ID, Int, Int) async throws -> GameSnapshot = {
    _, _, _ in
    throw GameTimerError.invalidCorrection
  }
  public var startOrResume: @Sendable (Game.ID, Int?) async throws -> GameTimerUpdate

  public init(
    cancelAlarm: @escaping @Sendable (Game.ID) async -> Void,
    endPresentation: @escaping @Sendable (Game.ID) async -> Void,
    pause: @escaping @Sendable (Game.ID, Int?) async throws -> GameSnapshot,
    reconcile: @escaping @Sendable (Game.ID) async throws -> GameSnapshot,
    refreshActivity: @escaping @Sendable (Game.ID) async -> Void,
    scheduleAlarm: @escaping @Sendable (Game.ID) async -> Bool,
    skip: @escaping @Sendable (Game.ID, Int?) async throws -> GameSnapshot,
    setRemainingTime: (@Sendable (Game.ID, Int, Int) async throws -> GameSnapshot)? = nil,
    startOrResume: @escaping @Sendable (Game.ID, Int?) async throws -> GameTimerUpdate
  ) {
    self.cancelAlarm = cancelAlarm
    self.endPresentation = endPresentation
    self.pause = pause
    self.reconcile = reconcile
    self.refreshActivity = refreshActivity
    self.scheduleAlarm = scheduleAlarm
    self.skip = skip
    if let setRemainingTime { self.setRemainingTime = setRemainingTime }
    self.startOrResume = startOrResume
  }
}

extension DependencyValues {
  nonisolated public var gameTimer: GameTimerClient {
    get { self[GameTimerClientKey.self] }
    set { self[GameTimerClientKey.self] = newValue }
  }
}

private nonisolated enum GameTimerClientKey: DependencyKey {
  static var liveValue: GameTimerClient { .live }
  static var previewValue: GameTimerClient { .live }
  static var testValue: GameTimerClient { .unimplemented }
}

/// Stable UI/intent adapter: commands commit through gameSession, then presentation runs.
nonisolated extension GameTimerClient {
  static public var live: Self {
    Self(
      cancelAlarm: { gameID in
        @Dependency(\.gamePresentation) var presentation
        await presentation.cancelAlarm(gameID)
      },
      endPresentation: { gameID in
        @Dependency(\.gamePresentation) var presentation
        await presentation.end(gameID)
      },
      pause: { gameID, expectedPhaseIndex in
        try await perform(gameID, command: .timing(.pause, expectedPhaseIndex: expectedPhaseIndex))
          .snapshot
      },
      reconcile: { gameID in
        try await perform(gameID, command: .reconcile).snapshot
      },
      refreshActivity: { gameID in
        @Dependency(\.gamePresentation) var presentation
        await presentation.refresh(gameID)
      },
      scheduleAlarm: { gameID in
        @Dependency(\.gamePresentation) var presentation
        return await presentation.scheduleAlarm(gameID)
      },
      skip: { gameID, expectedPhaseIndex in
        try await perform(gameID, command: .timing(.skip, expectedPhaseIndex: expectedPhaseIndex))
          .snapshot
      },
      setRemainingTime: { gameID, expectedPhaseIndex, seconds in
        try await perform(
          gameID,
          command: .timing(.setRemainingTime(seconds), expectedPhaseIndex: expectedPhaseIndex)
        ).snapshot
      },
      startOrResume: { gameID, expectedPhaseIndex in
        try await perform(
          gameID, command: .timing(.startOrResume, expectedPhaseIndex: expectedPhaseIndex))
      }
    )
  }

  static public var unimplemented: Self {
    Self(
      cancelAlarm: { _ in reportIssue("GameTimerClient.cancelAlarm is unimplemented") },
      endPresentation: { _ in reportIssue("GameTimerClient.endPresentation is unimplemented") },
      pause: { _, _ in
        reportIssue("GameTimerClient.pause is unimplemented")
        throw GameSessionRejection.stalePhase
      },
      reconcile: { _ in
        reportIssue("GameTimerClient.reconcile is unimplemented")
        throw GameSessionRejection.stalePhase
      },
      refreshActivity: { _ in reportIssue("GameTimerClient.refreshActivity is unimplemented") },
      scheduleAlarm: { _ in
        reportIssue("GameTimerClient.scheduleAlarm is unimplemented")
        return false
      },
      skip: { _, _ in
        reportIssue("GameTimerClient.skip is unimplemented")
        throw GameSessionRejection.stalePhase
      },
      setRemainingTime: { _, _, _ in
        reportIssue("GameTimerClient.setRemainingTime is unimplemented")
        throw GameTimerError.invalidCorrection
      },
      startOrResume: { _, _ in
        reportIssue("GameTimerClient.startOrResume is unimplemented")
        throw GameSessionRejection.stalePhase
      }
    )
  }

  private static func perform(_ gameID: Game.ID, command: GameSessionCommand) async throws
    -> GameTimerUpdate
  {
    @Dependency(\.date.now) var now
    @Dependency(\.gameSession) var session
    @Dependency(\.gamePresentation) var presentation
    let update = try await session.execute(gameID, command, now)
    guard !update.snapshot.game.isPlanned else { throw GameSessionRejection.gameNotStarted }
    if case .timing(.setRemainingTime, _) = command, update.outcome != .applied {
      throw GameTimerError.invalidCorrection
    }
    let schedulingFailed = await presentation.update(update, command)
    return GameTimerUpdate(alarmSchedulingFailed: schedulingFailed, snapshot: update.snapshot)
  }
}

private nonisolated enum GameTimerError: Error, LocalizedError {
  case invalidCorrection

  var errorDescription: String? {
    "The clock has changed. Close the editor and pause the current clock before trying again."
  }
}

extension GameTimerClient {
  static nonisolated public func elapsedSeconds(
    durationSeconds: Int,
    persistedElapsedSeconds: Int,
    timerEndsAt: Date?,
    now: Date
  ) -> Int {
    GameCountdown(elapsedSeconds: persistedElapsedSeconds, endsAt: timerEndsAt)
      .projection(durationSeconds: durationSeconds, now: now).elapsedSeconds
  }

  static nonisolated public func endDate(
    durationSeconds: Int,
    elapsedSeconds: Int,
    now: Date
  ) -> Date? {
    GameCountdown(elapsedSeconds: elapsedSeconds).endDate(
      durationSeconds: durationSeconds, now: now)
  }
}
