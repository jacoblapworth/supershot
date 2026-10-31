@testable import AlarmClient
import AppUI
import Clocks
import ConcurrencyExtras
import CustomDump
@testable import Database
import Dependencies
import DependenciesTestSupport
import FeatureFlagsClient
import Foundation
@testable import GameCore
@testable import GameServices
@testable import SharedModels
@testable import SubscriptionClient
import Testing
import TestSupport
@testable import UI
@testable import WidgetSupport

/// Test adapters independently of persistence and system services.
@MainActor
@Suite(.dependencies {
  $0.date.now = Date(timeIntervalSince1970: 1000)
  $0.proSubscription = .pro
})
struct GameAdapterTests {
  @Test func timerPresentsOnlyAfterCommandReturnsAuthoritativeState() async throws {
    let committed = LockIsolated(false)
    let expected = snapshot(running: true)
    let update = try await withDependencies {
      $0.gameSession.execute = { id, command, date in
        expectNoDifference(id, UUID(3))
        expectNoDifference(command, .timing(.startOrResume, expectedPhaseIndex: 0))
        expectNoDifference(date, Date(timeIntervalSince1970: 1000))
        committed.setValue(true)
        return GameSessionUpdate(outcome: .applied, snapshot: expected)
      }
      $0.gamePresentation.update = { result, _ in
        expectNoDifference(committed.value, true)
        expectNoDifference(result.snapshot, expected)
        return true
      }
    } operation: {
      try await GameTimerClient.live.startOrResume(UUID(3), 0)
    }
    expectNoDifference(update.snapshot, expected)
    expectNoDifference(update.alarmSchedulingFailed, true)
  }

  @Test func transactionFailureNeverRunsPresentation() async {
    enum Failure: Error { case storage }
    await withDependencies {
      $0.gameSession.execute = { _, _, _ in throw Failure.storage }
      // gamePresentation remains unimplemented: an accidental call reports a test failure.
    } operation: {
      await #expect(throws: Failure.self) { try await GameTimerClient.live.pause(UUID(3), 0) }
    }
  }

  @Test func rejectedStartRefreshesActivityWithoutSchedulingOrCancelling() async {
    let calls = LockIsolated<[String]>([])
    let rejected = GameSessionUpdate(outcome: .rejected(.confirmationRequired), snapshot: snapshot())
    let failed = await withDependencies {
      $0.alarmClient = AlarmClient(
        scheduleAlarm: { _ in
          calls.withValue { $0.append("schedule") }
          return true
        },
        updateActivity: { _, _ in calls.withValue { $0.append("refresh") } },
        cancelAlarm: { _, _ in calls.withValue { $0.append("cancel") } },
        endActivity: { _ in calls.withValue { $0.append("end") } }
      )
    } operation: {
      await GamePresentationClient.live.update(rejected, .timing(.startOrResume, expectedPhaseIndex: 0))
    }
    expectNoDifference(failed, false)
    expectNoDifference(calls.value, ["refresh"])
  }

  @Test func cancelledStartDoesNotScheduleAnAlarmAfterItsActivityUpdate() async {
    let clock = TestClock()
    let activityStarted = AsyncStream<Void>.makeStream()
    let calls = LockIsolated<[String]>([])
    let update = GameSessionUpdate(outcome: .applied, snapshot: snapshot(running: true))
    let task = Task {
      await withDependencies {
        $0.alarmClient = AlarmClient(
          scheduleAlarm: { _ in
            calls.withValue { $0.append("schedule") }
            return false
          },
          updateActivity: { _, _ in
            calls.withValue { $0.append("refresh") }
            activityStarted.continuation.yield(())
            try? await clock.sleep(for: .seconds(1))
          },
          cancelAlarm: { _, _ in },
          endActivity: { _ in }
        )
      } operation: {
        await GamePresentationClient.live.update(update, .timing(.startOrResume, expectedPhaseIndex: 0))
      }
    }
    for await _ in activityStarted.stream {
      break
    }
    task.cancel()
    _ = await task.value
    activityStarted.continuation.finish()
    expectNoDifference(calls.value, ["refresh"])
  }

  @Test(arguments: [true, false], [true, false])
  func capabilitiesAreIndependentWhenStarting(showsActivity: Bool, allowsAlerts: Bool) async {
    let calls = LockIsolated<[String]>([])
    let expected = snapshot(running: true)
    let failed = await withDependencies {
      $0.featureFlags = FeatureFlagsClient { feature, _ in
        switch feature {
        case .liveActivities: showsActivity
        case .timerAlerts: allowsAlerts
        }
      }
      $0.alarmClient = AlarmClient(
        scheduleAlarm: { snapshot in
          expectNoDifference(snapshot, expected)
          calls.withValue { $0.append("schedule") }
          return true
        },
        updateActivity: { snapshot, _ in
          expectNoDifference(snapshot, expected)
          calls.withValue { $0.append("refresh") }
        },
        cancelAlarm: { _, _ in calls.withValue { $0.append("cancel") } },
        endActivity: { _ in calls.withValue { $0.append("end") } }
      )
    } operation: {
      await GamePresentationClient.live.update(
        GameSessionUpdate(outcome: .applied, snapshot: expected),
        .timing(.startOrResume, expectedPhaseIndex: 0)
      )
    }
    expectNoDifference(failed, allowsAlerts)
    expectNoDifference(calls.value.filter { $0 == "refresh" }.count, showsActivity ? 1 : 0)
    expectNoDifference(calls.value.filter { $0 == "end" }.count, showsActivity ? 0 : 1)
    expectNoDifference(calls.value.filter { $0 == "schedule" }.count, allowsAlerts ? 1 : 0)
    expectNoDifference(calls.value.filter { $0 == "cancel" }.count, allowsAlerts ? 0 : 1)
  }

  @Test(arguments: [SubscriptionEntitlement.free, .unknown])
  func nonProAccessCleansUpBothPresentations(access: SubscriptionEntitlement) async {
    let calls = LockIsolated<[String]>([])
    await withDependencies {
      $0.proSubscription.currentAccess = { access }
      $0.alarmClient = AlarmClient(
        scheduleAlarm: { _ in Issue.record("Unexpected scheduling"); return false },
        updateActivity: { _, _ in Issue.record("Unexpected activity") },
        cancelAlarm: { _, _ in calls.withValue { $0.append("cancel") } },
        endActivity: { _ in calls.withValue { $0.append("end") } }
      )
    } operation: {
      _ = await GamePresentationClient.live.update(GameSessionUpdate(outcome: .unchanged, snapshot: snapshot(running: true)), .reconcile)
    }
    expectNoDifference(Set(calls.value), ["cancel", "end"])
  }

  @Test func finishingAlwaysCleansUpEvenWithIndependentOverrides() async {
    let calls = LockIsolated<[String]>([])
    await withDependencies {
      $0.featureFlags = FeatureFlagsClient { _, _ in true }
      $0.proSubscription.currentAccess = { Issue.record("Finish must not fetch access"); return .pro }
      $0.alarmClient = AlarmClient(
        scheduleAlarm: { _ in Issue.record("Unexpected scheduling"); return false },
        updateActivity: { _, _ in Issue.record("Unexpected activity") },
        cancelAlarm: { _, _ in calls.withValue { $0.append("cancel") } },
        endActivity: { _ in calls.withValue { $0.append("end") } }
      )
    } operation: {
      _ = await GamePresentationClient.live.update(GameSessionUpdate(outcome: .applied, snapshot: snapshot()), .finish)
    }
    expectNoDifference(calls.value, ["cancel", "end"])
  }

  private func snapshot(running: Bool = false) -> GameSnapshot {
    GameSnapshot(
      game: Game(
        id: UUID(3),
        startedAt: .distantPast,
        teamAID: UUID(1),
        teamBID: UUID(2),
        centrePassTeamID: UUID(1),
        timerEndsAt: running ? Date(timeIntervalSince1970: 1900) : nil
      ),
      goals: [],
      periods: testGamePeriods(gameID: UUID(3)),
      teamA: Team(id: UUID(1), name: "A"),
      teamB: Team(id: UUID(2), name: "B")
    )
  }
}
