import Database
import Dependencies
import DependenciesMacros
import Foundation
import GameCore
import SharedModels

#if os(iOS)
  import ActivityKit
  import AlarmKit
  import SwiftUI
#endif

nonisolated public struct AlarmClient: Sendable {
  public var scheduleAlarm: @Sendable (GameSnapshot) async -> Bool
  public var updateActivity: @Sendable (GameSnapshot, Bool) async -> Void
  public var cancelAlarm: @Sendable (Game.ID, Int) async -> Void
  public var reconcileAlarms: @Sendable (Set<Game.ID>) async -> Void
  public var endActivity: @Sendable (Game.ID) async -> Void

  public init(
    scheduleAlarm: @escaping @Sendable (GameSnapshot) async -> Bool,
    updateActivity: @escaping @Sendable (GameSnapshot, Bool) async -> Void,
    cancelAlarm: @escaping @Sendable (Game.ID, Int) async -> Void,
    reconcileAlarms: @escaping @Sendable (Set<Game.ID>) async -> Void = { _ in },
    endActivity: @escaping @Sendable (Game.ID) async -> Void
  ) {
    self.reconcileAlarms = reconcileAlarms
    self.scheduleAlarm = scheduleAlarm
    self.updateActivity = updateActivity
    self.cancelAlarm = cancelAlarm
    self.endActivity = endActivity
  }
}

extension DependencyValues {
  @DependencyEntry(
    liveValue: AlarmClient.noop,
    previewValue: AlarmClient.noop
  )
  nonisolated public var alarmClient: AlarmClient = .noop
}

nonisolated extension AlarmClient {
  static public let noop = Self(
    scheduleAlarm: { _ in false },
    updateActivity: { _, _ in },
    cancelAlarm: { _, _ in },
    endActivity: { _ in }
  )
}
