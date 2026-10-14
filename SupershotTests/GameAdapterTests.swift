import Clocks
import ConcurrencyExtras
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import Testing

@testable import Supershot

// Test adapters independently of persistence and system services.
@MainActor
@Suite(
  .dependencies {
    $0.date.now = Date(timeIntervalSince1970: 1_000)
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
        expectNoDifference(date, Date(timeIntervalSince1970: 1_000))
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
    let rejected = GameSessionUpdate(
      outcome: .rejected(.confirmationRequired), snapshot: snapshot())
    let failed = await withDependencies {
      $0.alarmClient = AlarmClient(
        scheduleAlarm: { _ in
          calls.withValue { $0.append("schedule") }
          return true
        },
        updateActivity: { _, _ in calls.withValue { $0.append("refresh") } },
        cancelAlarm: { _, _ in calls.withValue { $0.append("cancel") } },
        endActivity: { _ in calls.withValue { $0.append("end") } })
    } operation: {
      await GamePresentationClient.live.update(
        rejected, .timing(.startOrResume, expectedPhaseIndex: 0))
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
          cancelAlarm: { _, _ in }, endActivity: { _ in })
      } operation: {
        await GamePresentationClient.live.update(
          update, .timing(.startOrResume, expectedPhaseIndex: 0))
      }
    }
    for await _ in activityStarted.stream { break }
    task.cancel()
    _ = await task.value
    activityStarted.continuation.finish()
    expectNoDifference(calls.value, ["refresh"])
  }

  private func snapshot(running: Bool = false) -> GameSnapshot {
    GameSnapshot(
      game: Game(
        id: UUID(3), startedAt: .distantPast,
        teamAID: UUID(1), teamBID: UUID(2), centrePassTeamID: UUID(1),
        timerEndsAt: running ? Date(timeIntervalSince1970: 1_900) : nil),
      goals: [], periods: testGamePeriods(gameID: UUID(3)),
      teamA: Team(id: UUID(1), name: "A"), teamB: Team(id: UUID(2), name: "B"))
  }
}
