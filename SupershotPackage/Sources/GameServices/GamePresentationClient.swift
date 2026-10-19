import AlarmClient
import Database
import Dependencies
import FeatureFlagsClient
import Foundation
import GameCore
import IssueReporting
import SQLiteData
import SharedModels
import SubscriptionClient

/// System effects run only after the authoritative transaction has committed.
/// Presentation failure is reported separately and cannot roll back game state.
nonisolated public struct GamePresentationClient: Sendable {
  public var update: @Sendable (GameSessionUpdate, GameSessionCommand) async -> Bool
  public var cancelAlarm: @Sendable (Game.ID) async -> Void
  public var end: @Sendable (Game.ID) async -> Void
  public var refresh: @Sendable (Game.ID) async -> Void
  public var scheduleAlarm: @Sendable (Game.ID) async -> Bool

  static public var live: Self {
    Self(
      update: { update, command in
        @Dependency(\.alarmClient) var alarms
        @Dependency(\.proSubscription) var subscription
        @Dependency(\.featureFlags) var featureFlags
        let snapshot = update.snapshot
        let applied = update.outcome == .applied
        if command == .finish, applied {
          await end(alarms, snapshot: snapshot)
          return false
        }
        let access = (try? await subscription.currentAccess()) ?? .unknown
        let showsActivity = featureFlags.isEnabled(.liveActivities, access)
        let schedulesAlerts = featureFlags.isEnabled(.timerAlerts, access)
        if !schedulesAlerts {
          await alarms.cancelAlarm(snapshot.game.id, snapshot.phases.count)
        }
        if !showsActivity { await alarms.endActivity(snapshot.game.id) }
        guard showsActivity || schedulesAlerts else { return false }
        switch command {
        case .timing(.startOrResume, _) where applied:
          if showsActivity { await alarms.updateActivity(snapshot, true) }
          // A newer pause/reconcile can cancel the start effect after its commit.
          guard !Task.isCancelled, schedulesAlerts else { return false }
          return await alarms.scheduleAlarm(snapshot)
        case .timing(.pause, _) where applied && schedulesAlerts:
          await alarms.cancelAlarm(snapshot.game.id, snapshot.phases.count)
        case .timing(.skip, _) where applied && schedulesAlerts:
          await alarms.cancelAlarm(snapshot.game.id, snapshot.phases.count)
          if snapshot.game.timerEndsAt != nil { _ = await alarms.scheduleAlarm(snapshot) }
        case .timing(.setRemainingTime, _) where applied && schedulesAlerts:
          await alarms.cancelAlarm(snapshot.game.id, snapshot.phases.count)
        default:
          break
        }
        if showsActivity { await alarms.updateActivity(snapshot, true) }
        return false
      },
      cancelAlarm: { gameID in
        @Dependency(\.alarmClient) var alarms
        await alarms.cancelAlarm(gameID, await phaseCount(gameID))
      },
      end: { gameID in
        @Dependency(\.alarmClient) var alarms
        await alarms.cancelAlarm(gameID, await phaseCount(gameID))
        await alarms.endActivity(gameID)
      },
      refresh: { gameID in
        @Dependency(\.defaultDatabase) var database
        guard
          let snapshot = try? await database.read({ try GameSnapshot.fetch($0, gameID: gameID) })
        else { return }
        @Dependency(\.gamePresentation) var presentation
        _ = await presentation.update(
          GameSessionUpdate(outcome: .unchanged, snapshot: snapshot), .reconcile)
      },
      scheduleAlarm: { gameID in
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.alarmClient) var alarms
        @Dependency(\.proSubscription) var subscription
        @Dependency(\.featureFlags) var featureFlags
        guard
          let snapshot = try? await database.read({ try GameSnapshot.fetch($0, gameID: gameID) }),
          snapshot.game.timerEndsAt != nil
        else { return false }
        let access = (try? await subscription.currentAccess()) ?? .unknown
        guard featureFlags.isEnabled(.timerAlerts, access) else {
          await alarms.cancelAlarm(snapshot.game.id, snapshot.phases.count)
          return false
        }
        return await alarms.scheduleAlarm(snapshot)
      }
    )
  }

  static public var unimplemented: Self {
    Self(
      update: { _, _ in
        reportIssue("GamePresentationClient.update is unimplemented")
        return false
      },
      cancelAlarm: { _ in reportIssue("GamePresentationClient.cancelAlarm is unimplemented") },
      end: { _ in reportIssue("GamePresentationClient.end is unimplemented") },
      refresh: { _ in reportIssue("GamePresentationClient.refresh is unimplemented") },
      scheduleAlarm: { _ in
        reportIssue("GamePresentationClient.scheduleAlarm is unimplemented")
        return false
      }
    )
  }

  private static func end(_ alarms: AlarmClient, snapshot: GameSnapshot) async {
    await alarms.cancelAlarm(snapshot.game.id, snapshot.phases.count)
    await alarms.endActivity(snapshot.game.id)
  }

  private static func phaseCount(_ gameID: Game.ID) async -> Int {
    @Dependency(\.defaultDatabase) var database
    return
      (try? await database.read { db in
        let periods = try GamePeriod.where { $0.gameID.eq(gameID) }.fetchAll(db)
        return GameTimeline(periods: periods)?.phases.count ?? 0
      }) ?? 0
  }

  public init(
    update: @escaping @Sendable (GameSessionUpdate, GameSessionCommand) async -> Bool,
    cancelAlarm: @escaping @Sendable (Game.ID) async -> Void,
    end: @escaping @Sendable (Game.ID) async -> Void,
    refresh: @escaping @Sendable (Game.ID) async -> Void,
    scheduleAlarm: @escaping @Sendable (Game.ID) async -> Bool
  ) {
    self.update = update
    self.cancelAlarm = cancelAlarm
    self.end = end
    self.refresh = refresh
    self.scheduleAlarm = scheduleAlarm
  }
}

extension DependencyValues {
  nonisolated public var gamePresentation: GamePresentationClient {
    get { self[GamePresentationClientKey.self] }
    set { self[GamePresentationClientKey.self] = newValue }
  }
}

private nonisolated enum GamePresentationClientKey: DependencyKey {
  static var liveValue: GamePresentationClient { .live }
  static var testValue: GamePresentationClient { .unimplemented }
}
