import Database
import Dependencies
import DependenciesMacros
import FeatureFlagsClient
import Foundation
import GameCore
import SharedModels
import SQLiteData
import SubscriptionClient

#if os(iOS)
  import ActivityKit
  import AlarmKit
  import SwiftUI
#endif

public nonisolated struct AlarmClient: Sendable {
  public var scheduleAlarm: @Sendable (GameSnapshot) async -> Bool
  public var updateActivity: @Sendable (GameSnapshot, Bool) async -> Void
  public var cancelAlarm: @Sendable (Game.ID, Int) async -> Void
  public var reconcileAlarms: @Sendable (Set<Game.ID>) async -> Void
  public var reconcileActivities: @Sendable (Set<Game.ID>) async -> Void
  public var endActivity: @Sendable (Game.ID) async -> Void

  public init(
    scheduleAlarm: @escaping @Sendable (GameSnapshot) async -> Bool,
    updateActivity: @escaping @Sendable (GameSnapshot, Bool) async -> Void,
    cancelAlarm: @escaping @Sendable (Game.ID, Int) async -> Void,
    reconcileAlarms: @escaping @Sendable (Set<Game.ID>) async -> Void = { _ in },
    reconcileActivities: @escaping @Sendable (Set<Game.ID>) async -> Void = { _ in },
    endActivity: @escaping @Sendable (Game.ID) async -> Void
  ) {
    self.reconcileAlarms = reconcileAlarms
    self.reconcileActivities = reconcileActivities
    self.scheduleAlarm = scheduleAlarm
    self.updateActivity = updateActivity
    self.cancelAlarm = cancelAlarm
    self.endActivity = endActivity
  }
}

public extension DependencyValues {
  @DependencyEntry(
    liveValue: AlarmClient.noop,
    previewValue: AlarmClient.noop
  )
  nonisolated var alarmClient: AlarmClient = .noop
}

public nonisolated extension AlarmClient {
  /// Revalidate queued work against current capability access and committed timer state.
  static func canSchedule(_ snapshot: GameSnapshot) async -> Bool {
    @Dependency(\.defaultDatabase) var database
    @Dependency(\.proSubscription) var subscription
    @Dependency(\.featureFlags) var featureFlags
    guard !Task.isCancelled,
          await featureFlags.isEnabled(.timerAlerts, (try? subscription.currentAccess()) ?? .unknown),
          let current = try? await database.read({ try GameSnapshot.fetch($0, gameID: snapshot.game.id) })
    else { return false }
    return current.game.isInProgress && current.game.timing == snapshot.game.timing
  }

  static let noop = Self(
    scheduleAlarm: { _ in false },
    updateActivity: { _, _ in },
    cancelAlarm: { _, _ in },
    endActivity: { _ in }
  )
}
