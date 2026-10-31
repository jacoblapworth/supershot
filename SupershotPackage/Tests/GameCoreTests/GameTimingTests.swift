import CustomDump
import Dependencies
import Foundation
@testable import GameCore
@testable import SharedModels
import Testing
import TestSupport

/// No database-backed suite, TCA store, or system presentation dependencies.
struct GameTimingTests {
  @Test(arguments: [BreakStartPolicy.automatic, .manual])
  func delayedReconciliationProducesOrderedFactsOnce(policy: BreakStartPolicy) throws {
    let timeline = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 120)))
    let boundary = Date(timeIntervalSince1970: 1000)
    var timing = GameTimingState(phaseIndex: 0, countdown: GameCountdown(endsAt: boundary), breakStartPolicy: policy)
    let transitions = timing.reconcile(in: timeline, now: boundary.addingTimeInterval(200))
    var expected: [GameTimingTransition] = [
      .periodCompleted(testGamePeriodReference(number: 1), boundary: boundary, hasFollowingPeriod: true),
    ]
    if policy == .automatic {
      expected.append(.breakCompleted(testGamePeriodReference(number: 1), boundary: boundary.addingTimeInterval(120)))
    }
    expectNoDifference(transitions, expected)
    expectNoDifference(timing.phaseIndex, policy == .automatic ? 2 : 1)
    expectNoDifference(timing.countdown, GameCountdown())
    expectNoDifference(timing.reconcile(in: timeline, now: boundary.addingTimeInterval(300)), [])
  }

  @Test func commandsRejectStalePhasesAndPreservePausedCorrection() throws {
    let timeline = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 2)))
    let now = Date(timeIntervalSince1970: 1000)
    var timing = GameTimingState(phaseIndex: 0, countdown: GameCountdown())
    expectNoDifference(timing.apply(.startOrResume, in: timeline, expectedPhaseIndex: 1, now: now).status, .rejected)
    expectNoDifference(timing.countdown, GameCountdown())
    expectNoDifference(
      timing.apply(.setRemainingTime(600), in: timeline, expectedPhaseIndex: 0, now: now).status,
      .applied
    )
    expectNoDifference(timing.countdown, GameCountdown(elapsedSeconds: 300))
    expectNoDifference(
      timing.apply(.startOrResume, in: timeline, expectedPhaseIndex: 0, now: now).transitions,
      [.periodStarted(testGamePeriodReference(number: 1))]
    )
    expectNoDifference(
      timing.apply(.setRemainingTime(500), in: timeline, expectedPhaseIndex: 0, now: now).status,
      .rejected
    )
    _ = timing.apply(.pause, in: timeline, expectedPhaseIndex: 0, now: now.addingTimeInterval(30))
    expectNoDifference(timing.countdown, GameCountdown(elapsedSeconds: 330))
    _ = timing.apply(.startOrResume, in: timeline, expectedPhaseIndex: 0, now: now.addingTimeInterval(40))
    expectNoDifference(timing.countdown.endsAt, now.addingTimeInterval(610))
  }

  @Test func skippingOmittedBreakWaitsAndFinalCompletionIsIdempotent() throws {
    let timeline = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 2)))
    var timing = GameTimingState(phaseIndex: 0, countdown: GameCountdown())
    let first = timing.apply(.skip, in: timeline, expectedPhaseIndex: 0, now: .distantPast)
    expectNoDifference(
      first.transitions,
      [
        .periodCompleted(testGamePeriodReference(number: 1), boundary: .distantPast, hasFollowingPeriod: true),
      ]
    )
    expectNoDifference(timing.countdown, GameCountdown())
    _ = timing.apply(.skip, in: timeline, expectedPhaseIndex: 1, now: .distantPast)
    expectNoDifference(timing.isFinalPeriodComplete(in: timeline), true)
    expectNoDifference(timing.apply(.skip, in: timeline, expectedPhaseIndex: 1, now: .distantPast).status, .unchanged)
    expectNoDifference(
      timing.apply(.startOrResume, in: timeline, expectedPhaseIndex: 1, now: .distantPast).status,
      .unchanged
    )
  }
}

extension GameTimingTests {
  @Test(arguments: [0, 1, 120])
  func phaseStatusComesFromElapsedTimeAndCorrections(elapsed: Int) throws {
    let timeline = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 2)))
    let now = Date(timeIntervalSince1970: 1000)
    var timing = GameTimingState(phaseIndex: 0, countdown: GameCountdown())
    expectNoDifference(timing.status(in: timeline), .ready)
    _ = timing.apply(.startOrResume, in: timeline, expectedPhaseIndex: 0, now: now)
    expectNoDifference(timing.status(in: timeline), .running)
    _ = timing.apply(
      .pause,
      in: timeline,
      expectedPhaseIndex: 0,
      now: now.addingTimeInterval(TimeInterval(elapsed))
    )
    expectNoDifference(timing.status(in: timeline), elapsed == 0 ? .ready : .paused)
    _ = timing.apply(.setRemainingTime(900), in: timeline, expectedPhaseIndex: 0, now: now)
    expectNoDifference(timing.status(in: timeline), .ready)
    _ = timing.apply(.setRemainingTime(600), in: timeline, expectedPhaseIndex: 0, now: now)
    expectNoDifference(timing.status(in: timeline), .paused)
    let restart = timing.apply(.startOrResume, in: timeline, expectedPhaseIndex: 0, now: now)
    expectNoDifference(restart.transitions, [.periodStarted(testGamePeriodReference(number: 1))])
    _ = timing.apply(.skip, in: timeline, expectedPhaseIndex: 0, now: now)
    expectNoDifference(timing.phaseIndex, 1)
    expectNoDifference(timing.status(in: timeline), .ready)
  }

  @Test(arguments: [BreakStartPolicy.automatic, .manual])
  func breakStatusFollowsPolicyAndNextQuarterIsReady(policy: BreakStartPolicy) throws {
    let timeline = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 120)))
    var timing = GameTimingState(phaseIndex: 0, countdown: GameCountdown(), breakStartPolicy: policy)
    _ = timing.apply(.skip, in: timeline, expectedPhaseIndex: 0, now: .distantPast)
    expectNoDifference(timing.status(in: timeline), policy == .automatic ? .running : .ready)
    _ = timing.apply(.skip, in: timeline, expectedPhaseIndex: 1, now: .distantPast)
    expectNoDifference(timing.status(in: timeline), .ready)
  }
}
