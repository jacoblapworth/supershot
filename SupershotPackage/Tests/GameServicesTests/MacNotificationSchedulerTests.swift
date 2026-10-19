#if os(macOS)
  import ConcurrencyExtras
  import Foundation
  import Dependencies
  import Testing
  import TestSupport
  @testable import AlarmClient
  @testable import Database
  @testable import GameCore
  @testable import SharedModels

  @Suite struct MacNotificationSchedulerTests {
    private func snapshot(policy: BreakStartPolicy = .automatic, end: TimeInterval? = 1100)
      -> GameSnapshot
    {
      var game = Game(
        id: UUID(3), startedAt: Date(timeIntervalSince1970: 500),
        teamAID: UUID(1), teamBID: UUID(2), centrePassTeamID: UUID(1))
      game.breakStartPolicy = policy
      game.timerEndsAt = end.map(Date.init(timeIntervalSince1970:))
      return GameSnapshot(
        game: game, goals: [],
        periods: testGamePeriods(
          gameID: game.id, count: 2, durationSeconds: 100, breakDurationSeconds: 60),
        teamA: Team(id: UUID(1), name: "Ravens"), teamB: Team(id: UUID(2), name: "Swifts"))
    }

    @Test(arguments: [BreakStartPolicy.automatic, .manual])
    func schedulesOnlyKnownBoundariesAndReplacesRequests(policy: BreakStartPolicy) async {
      let harness = NotificationHarness()
      let scheduler = MacNotificationScheduler(
        delivery: harness.client,
        now: { Date(timeIntervalSince1970: 1000) }, isCurrent: { _ in true })
      #expect(await scheduler.schedule(snapshot(policy: policy)) == false)
      #expect(await harness.requests.count == (policy == .automatic ? 2 : 1))
      #expect(
        await harness.requests.values.map(\.date).sorted()
          == (policy == .automatic ? [1100.0, 1160.0] : [1100.0]).map(
            Date.init(timeIntervalSince1970:)))
      #expect(await scheduler.schedule(snapshot(policy: policy, end: 1200)) == false)
      #expect(await harness.requests.values.map(\.date).min() == Date(timeIntervalSince1970: 1200))
      await scheduler.cancel(UUID(3))
      #expect(await harness.requests.isEmpty)
    }

    @Test func deniedPausedAndStaleGamesDoNotSchedule() async {
      let harness = NotificationHarness()
      await harness.setAuthorization(.denied)
      let scheduler = MacNotificationScheduler(
        delivery: harness.client,
        now: { Date(timeIntervalSince1970: 1000) }, isCurrent: { _ in true })
      #expect(await scheduler.schedule(snapshot()) == false)
      #expect(await harness.requests.isEmpty)
      await harness.setAuthorization(.authorized)
      #expect(await scheduler.schedule(snapshot(end: nil)) == false)
      #expect(await harness.requests.isEmpty)
      let stale = MacNotificationScheduler(delivery: harness.client, isCurrent: { _ in false })
      #expect(await stale.schedule(snapshot()) == false)
      #expect(await harness.requests.isEmpty)
    }

    @Test func partialFailureRollsBackRequestsAndReportsFailure() async {
      let harness = NotificationHarness()
      await harness.failAfter(1)
      let scheduler = MacNotificationScheduler(
        delivery: harness.client,
        now: { Date(timeIntervalSince1970: 1000) }, isCurrent: { _ in true })
      #expect(await scheduler.schedule(snapshot()))
      #expect(await harness.requests.isEmpty)
    }

    @Test func reconciliationRemovesOrphansAndDeliveredNotifications() async {
      let harness = NotificationHarness()
      let id = MacNotificationScheduler.prefix(UUID(3)) + "0"
      await harness.setDelivered([id, "another.feature"])
      let scheduler = MacNotificationScheduler(delivery: harness.client, isCurrent: { _ in true })
      await scheduler.reconcile(keeping: [])
      #expect(await harness.delivered == ["another.feature"])
    }

    @Test func lateStaleScheduleCannotSuppressANewerDeadline() async {
      await withMainSerialExecutor {
        let harness = NotificationHarness()
        let gate = AsyncStream<Void>.makeStream()
        await harness.suspendAdd(until: gate.stream)
        let deadline = Date(timeIntervalSince1970: 1200)
        let scheduler = MacNotificationScheduler(
          delivery: harness.client,
          now: { Date(timeIntervalSince1970: 1000) },
          isCurrent: { $0.game.timerEndsAt == deadline })
        let current = snapshot(end: 1200)
        let stale = snapshot(end: 1100)
        let scheduling = Task { await scheduler.schedule(current) }
        await Task.megaYield()
        let staleScheduling = Task { await scheduler.schedule(stale) }
        await Task.megaYield()
        gate.continuation.finish()
        _ = await scheduling.value
        _ = await staleScheduling.value
        #expect(await harness.requests.count == 2)
        #expect(await harness.requests.values.map(\.date).min() == deadline)
      }
    }

    @Test func cancellingDuringAnAddCannotRestoreTheNotification() async {
      await withMainSerialExecutor {
        let harness = NotificationHarness()
        let gate = AsyncStream<Void>.makeStream()
        await harness.suspendAdd(until: gate.stream)
        let scheduler = MacNotificationScheduler(
          delivery: harness.client,
          now: { Date(timeIntervalSince1970: 1000) }, isCurrent: { _ in true })
        let current = snapshot()
        let scheduling = Task { await scheduler.schedule(current) }
        await Task.megaYield()
        let cancelling = Task { await scheduler.cancel(UUID(3)) }
        await Task.megaYield()
        gate.continuation.finish()
        _ = await scheduling.value
        await cancelling.value
        #expect(await harness.requests.isEmpty)
      }
    }
  }

  private actor NotificationHarness {
    var requests: [String: GameNotificationRequest] = [:]
    var delivered: [String] = []
    var authorization = AlarmAuthorizationStatus.authorized
    var maximumAdds: Int?
    var gate: AsyncStream<Void>?
    nonisolated var client: NotificationDeliveryClient {
      NotificationDeliveryClient(
        authorization: { await self.authorization }, add: { try await self.add($0) },
        pendingIDs: { await Array(self.requests.keys) }, deliveredIDs: { await self.delivered },
        remove: { await self.remove($0) })
    }
    func setAuthorization(_ value: AlarmAuthorizationStatus) { authorization = value }
    func failAfter(_ count: Int) { maximumAdds = count }
    func setDelivered(_ ids: [String]) { delivered = ids }
    func suspendAdd(until stream: AsyncStream<Void>) { gate = stream }
    func add(_ request: GameNotificationRequest) async throws {
      if let gate { for await _ in gate {} }
      if let maximumAdds, requests.count >= maximumAdds { throw Failure.unavailable }
      requests[request.id] = request
    }
    func remove(_ ids: [String]) {
      for id in ids { requests[id] = nil }
      delivered.removeAll { ids.contains($0) }
    }
    enum Failure: Error { case unavailable }
  }
#endif
