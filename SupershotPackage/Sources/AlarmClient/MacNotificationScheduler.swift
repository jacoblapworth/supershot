#if os(macOS)
  import Database
  import Dependencies
  import FeatureFlagsClient
  import Foundation
  import GameCore
  import SharedModels
  import SQLiteData
  import SubscriptionClient
  import UserNotifications

  nonisolated package struct GameNotificationRequest: Equatable, Sendable {
    package var id: String
    package var date: Date
    package var title: String
    package var body: String
    package var gameID: Game.ID
  }

  /// A small boundary lets scheduling and races be tested without system permission prompts.
  nonisolated package struct NotificationDeliveryClient: Sendable {
    package var authorization: @Sendable () async -> AlarmAuthorizationStatus
    package var add: @Sendable (GameNotificationRequest) async throws -> Void
    package var pendingIDs: @Sendable () async -> [String]
    package var deliveredIDs: @Sendable () async -> [String]
    package var remove: @Sendable ([String]) async -> Void

    package static var live: Self {
      let center = UNUserNotificationCenter.current()
      return Self(
        authorization: { await macNotificationAuthorization() },
        add: { request in
          let content = UNMutableNotificationContent()
          content.title = request.title
          content.body = request.body
          content.sound = .default
          content.userInfo = ["gameID": request.gameID.uuidString]
          let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(0.1, request.date.timeIntervalSinceNow), repeats: false)
          try await center.add(
            UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
        },
        pendingIDs: { await center.pendingNotificationRequests().map(\.identifier) },
        deliveredIDs: { await center.deliveredNotifications().map { $0.request.identifier } },
        remove: { ids in
          center.removePendingNotificationRequests(withIdentifiers: ids)
          center.removeDeliveredNotifications(withIdentifiers: ids)
        }
      )
    }
  }

  /// Operations for one game are ordered across awaits. Cancellation invalidates queued scheduling work.
  package actor MacNotificationScheduler {
    private let delivery: NotificationDeliveryClient
    private let isCurrent: @Sendable (GameSnapshot) async -> Bool
    private let now: @Sendable () -> Date
    private var revisions: [Game.ID: Int] = [:]
    private var cancellations: [Game.ID: Int] = [:]
    private var tasks: [Game.ID: Task<Bool, Never>] = [:]

    package init(
      delivery: NotificationDeliveryClient,
      now: @escaping @Sendable () -> Date = { Date() },
      isCurrent: @escaping @Sendable (GameSnapshot) async -> Bool
    ) {
      self.delivery = delivery
      self.now = now
      self.isCurrent = isCurrent
    }

    package func schedule(_ snapshot: GameSnapshot) async -> Bool {
      let id = snapshot.game.id
      let revision = nextRevision(id)
      let cancellation = cancellations[id, default: 0]
      let previous = tasks[id]
      let task = Task {
        _ = await previous?.value
        guard self.cancellations[id, default: 0] == cancellation, await self.isCurrent(snapshot),
          self.cancellations[id, default: 0] == cancellation
        else { return false }
        await self.removeRequests(for: id)
        guard self.cancellations[id, default: 0] == cancellation,
          await self.delivery.authorization() == .authorized,
          self.cancellations[id, default: 0] == cancellation
        else { return false }
        let alarms = ScheduledGameAlarm.plan(
          timeline: snapshot.timeline, progress: snapshot.game.timing)
        do {
          for alarm in alarms where alarm.date > self.now() {
            guard self.cancellations[id, default: 0] == cancellation else { break }
            let title: String
            switch alarm.phase {
            case .period(let period, _): title = "Quarter \(period.number) ended"
            case .breakTime: title = "Break ended"
            }
            try await self.delivery.add(
              GameNotificationRequest(
                id: Self.prefix(id) + String(alarm.phaseIndex), date: alarm.date,
                title: title, body: "\(snapshot.teamA.name) vs \(snapshot.teamB.name)", gameID: id))
            if self.cancellations[id, default: 0] != cancellation {
              await self.removeRequests(for: id)
              break
            }
          }
          return false
        } catch {
          await self.removeRequests(for: id)
          return self.cancellations[id, default: 0] == cancellation
        }
      }
      tasks[id] = task
      let failed = await task.value
      if revisions[id] == revision { tasks[id] = nil }
      return failed
    }

    package func cancel(_ id: Game.ID) async {
      let revision = nextRevision(id)
      cancellations[id, default: 0] += 1
      let previous = tasks[id]
      let task = Task {
        _ = await previous?.value
        await self.removeRequests(for: id)
        return false
      }
      tasks[id] = task
      _ = await task.value
      if revisions[id] == revision { tasks[id] = nil }
    }

    package func reconcile(keeping gameIDs: Set<Game.ID>) async {
      let pending = await delivery.pendingIDs()
      let delivered = await delivery.deliveredIDs()
      let ids = Set((pending + delivered).compactMap(Self.gameID))
      for id in ids.union(tasks.keys) where !gameIDs.contains(id) { await cancel(id) }
    }

    private func nextRevision(_ id: Game.ID) -> Int {
      revisions[id, default: 0] += 1
      return revisions[id]!
    }
    private func removeRequests(for id: Game.ID) async {
      let pending = await delivery.pendingIDs()
      let delivered = await delivery.deliveredIDs()
      await delivery.remove(
        Array(Set(pending + delivered).filter { $0.hasPrefix(Self.prefix(id)) }))
    }
    package nonisolated static func prefix(_ id: Game.ID) -> String {
      "supershot.game.\(id.uuidString).phase."
    }
    private nonisolated static func gameID(_ identifier: String) -> Game.ID? {
      let components = identifier.split(separator: ".")
      guard components.count == 5, components[0] == "supershot", components[1] == "game",
        components[3] == "phase"
      else { return nil }
      return UUID(uuidString: String(components[2]))
    }
  }

  nonisolated extension AlarmClient {
    public static var macNotifications: Self { macNotifications(delivery: .live) }

    package static func macNotifications(delivery: NotificationDeliveryClient) -> Self {
      @Dependency(\.defaultDatabase) var database
      @Dependency(\.proSubscription) var subscription
      @Dependency(\.featureFlags) var featureFlags
      @Dependency(\.date) var date
      let scheduler = MacNotificationScheduler(delivery: delivery, now: { date.now }) { snapshot in
        guard !Task.isCancelled,
          featureFlags.isEnabled(.timerAlerts, (try? await subscription.currentAccess()) ?? .unknown)
        else {
          return false
        }
        // A delayed start effect must not restore notifications after a newer game transaction.
        guard
          let current = try? await database.read({
            try GameSnapshot.fetch($0, gameID: snapshot.game.id)
          })
        else { return false }
        return current.game.endedAt == nil && current.game.timing == snapshot.game.timing
      }
      return Self(
        scheduleAlarm: { await scheduler.schedule($0) },
        updateActivity: { _, _ in },
        cancelAlarm: { id, _ in await scheduler.cancel(id) },
        reconcileAlarms: { await scheduler.reconcile(keeping: $0) },
        endActivity: { _ in }
      )
    }
  }
#endif
