@testable import AlarmClient
import CustomDump
@testable import Database
import Dependencies
import Foundation
@testable import GameCore
@testable import ScoringFeature
@testable import SharedModels
import SQLiteData
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  struct GameTimelineTests {
    @Test(arguments: [0.0, 30.0, 5000.0])
    func expiredBreakRetainsItsBoundaryWithoutAdvancingPlayingTime(delay: Double) throws {
      let timeline = try #require(GameTimeline(periods:
        testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 120)))
      let boundary = Date(timeIntervalSince1970: 1000)
      var timing = GameTimingState(phaseIndex: 1, countdown: .init(endsAt: boundary))
      timing.reconcile(in: timeline, now: boundary.addingTimeInterval(delay))
      #expect(timing.phaseIndex == 2)
      #expect(timing.countdown == GameCountdown())
      #expect(timing.waitingSince == boundary)
      #expect(GameClockPresentation.resolve(
        phase: timeline.phases[2],
        countdown: timing.countdown,
        waitingSince: timing.waitingSince,
        now: boundary.addingTimeInterval(delay)
      )
        == .waiting(since: boundary, elapsedSeconds: Int(delay)))
      timing.reconcile(in: timeline, now: boundary.addingTimeInterval(delay + 50))
      #expect(timing.waitingSince == boundary)
      let result = timing.apply(
        .startOrResume,
        in: timeline,
        expectedPhaseIndex: 2,
        now: boundary.addingTimeInterval(delay + 50)
      )
      #expect(result.status == .applied)
      #expect(timing.waitingSince == nil)
      #expect(timing.countdown.endsAt == boundary.addingTimeInterval(delay + 950))
    }

    @Test
    func breakPresentationCrossesZeroWithoutChangingCountdown() throws {
      let timeline = try #require(GameTimeline(periods:
        testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 120)))
      let boundary = Date(timeIntervalSince1970: 1000)
      let countdown = GameCountdown(endsAt: boundary)
      #expect(GameClockPresentation.resolve(
        phase: timeline.phases[1],
        countdown: countdown,
        waitingSince: nil,
        now: boundary.addingTimeInterval(-0.1)
      )
        == .countdown(.init(elapsedSeconds: 119, remainingSeconds: 1, status: .running)))
      for seconds in [0, 30] {
        #expect(GameClockPresentation.resolve(
          phase: timeline.phases[1],
          countdown: countdown,
          waitingSince: nil,
          now: boundary.addingTimeInterval(Double(seconds))
        )
          == .waiting(since: boundary, elapsedSeconds: seconds))
      }
      for phase in [timeline.phases[0], timeline.phases[2]] {
        #expect(GameClockPresentation.breakBoundary(phase: phase, countdown: countdown, waitingSince: nil) == nil)
      }
      #expect(GameClockPresentation.breakBoundary(phase: timeline.phases[1], countdown: .init(), waitingSince: nil) == nil)
      #expect(GameClockPresentation.breakBoundary(phase: timeline.phases[1], countdown: .init(elapsedSeconds: 50), waitingSince: nil) == nil)
    }

    @Test
    func correctedResumedManualBreakUsesItsNewDeadline() throws {
      let timeline = try #require(GameTimeline(periods:
        testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 120)))
      let start = Date(timeIntervalSince1970: 1000)
      var timing = GameTimingState(phaseIndex: 1, countdown: .init(), breakStartPolicy: .manual)
      _ = timing.apply(.startOrResume, in: timeline, expectedPhaseIndex: 1, now: start)
      _ = timing.apply(.pause, in: timeline, expectedPhaseIndex: 1, now: start.addingTimeInterval(30))
      timing.reconcile(in: timeline, now: start.addingTimeInterval(500))
      #expect(timing.phaseIndex == 1)
      #expect(timing.waitingSince == nil)
      _ = timing.apply(.setRemainingTime(10), in: timeline, expectedPhaseIndex: 1, now: start.addingTimeInterval(500))
      _ = timing.apply(.startOrResume, in: timeline, expectedPhaseIndex: 1, now: start.addingTimeInterval(500))
      timing.reconcile(in: timeline, now: start.addingTimeInterval(540))
      #expect(timing.waitingSince == start.addingTimeInterval(510))
      #expect(timing.countdown == GameCountdown())
      // Correcting the next quarter doesn't turn the wait into playing time.
      _ = timing.apply(.setRemainingTime(850), in: timeline, expectedPhaseIndex: 2, now: start.addingTimeInterval(540))
      #expect(GameClockPresentation.resolve(
        phase: timeline.phases[2],
        countdown: timing.countdown,
        waitingSince: timing.waitingSince,
        now: start.addingTimeInterval(540)
      )
        == .waiting(since: start.addingTimeInterval(510), elapsedSeconds: 30))
      _ = timing.apply(.startOrResume, in: timeline, expectedPhaseIndex: 2, now: start.addingTimeInterval(540))
      #expect(timing.waitingSince == nil)
      #expect(timing.countdown.endsAt == start.addingTimeInterval(1390))
    }

    @Test
    func skipAndOmittedBreaksNeverCreateWaitingTime() throws {
      let boundary = Date(timeIntervalSince1970: 1000)
      let timeline = try #require(GameTimeline(periods:
        testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 120)))
      var timing = GameTimingState(phaseIndex: 1, countdown: .init(endsAt: boundary))
      _ = timing.apply(.skip, in: timeline, expectedPhaseIndex: 1, now: boundary.addingTimeInterval(-30))
      #expect(timing.waitingSince == nil)
      let omitted = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 2)))
      timing = GameTimingState(phaseIndex: 0, countdown: .init(endsAt: boundary))
      timing.reconcile(in: omitted, now: boundary.addingTimeInterval(30))
      #expect(timing.waitingSince == nil)
      timing.countdown.endsAt = boundary.addingTimeInterval(60)
      timing.reconcile(in: omitted, now: boundary.addingTimeInterval(100))
      #expect(timing.isFinalPeriodComplete(in: omitted))
      #expect(timing.waitingSince == nil)
    }

    @Test(arguments: [BreakStartPolicy.automatic, .manual], [0.0, 50.0, 1000.0])
    func breakStartPolicyControlsDelayedReconciliation(policy: BreakStartPolicy, delay: Double) throws {
      let timeline = try #require(GameTimeline(periods:
        testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 120)))
      let boundary = Date(timeIntervalSince1970: 1000)
      var progress = GameProgress(
        phaseIndex: 0,
        countdown: GameCountdown(endsAt: boundary),
        isAwaitingCentrePassConfirmation: false,
        breakStartPolicy: policy
      )
      let plan = ScheduledGameAlarm.plan(timeline: timeline, progress: progress.timing)
      #expect(plan.map(\.phaseIndex) == (policy == .automatic ? [0, 1] : [0]))
      progress.reconcile(in: timeline, now: boundary.addingTimeInterval(delay))
      #expect(progress.isAwaitingCentrePassConfirmation)
      #expect(progress.lateScoringPeriodNumber == 1)
      if policy == .manual {
        #expect(progress.phaseIndex == 1)
        #expect(progress.countdown == GameCountdown())
        #expect(ScheduledGameAlarm.plan(timeline: timeline, progress: progress.timing).isEmpty)
      } else if delay < 120 {
        #expect(progress.phaseIndex == 1)
        #expect(progress.countdown.endsAt == boundary.addingTimeInterval(120))
        #expect(progress.countdown.elapsedSeconds == Int(delay))
      } else {
        #expect(progress.phaseIndex == 2)
        #expect(progress.countdown == GameCountdown())
      }
    }

    @Test(arguments: [BreakStartPolicy.automatic, .manual])
    func policyDoesNotCreateOmittedOrFinalBreaks(policy: BreakStartPolicy) throws {
      let timeline = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 2)))
      var progress = GameProgress(
        phaseIndex: 0,
        countdown: GameCountdown(),
        isAwaitingCentrePassConfirmation: false,
        breakStartPolicy: policy
      )
      progress.complete(in: timeline, boundary: .distantPast)
      #expect(progress.phaseIndex == 1)
      #expect(progress.countdown == GameCountdown())
      progress.complete(in: timeline, boundary: .distantPast)
      #expect(progress.isFinalPeriodComplete(in: timeline))
      #expect(ScheduledGameAlarm.plan(timeline: timeline, progress: progress.timing).isEmpty)
    }

    @Test
    func unorderedPeriodsProducePhasesWithStableIdentityAndIndividualDurations() throws {
      var periods = testGamePeriods(gameID: UUID(3), count: 3, breakDurations: [120, 300])
      periods[1].durationSeconds = 600
      periods[2].durationSeconds = 1200
      let timeline = try #require(GameTimeline(periods: [periods[2], periods[0], periods[1]]))
      expectNoDifference(timeline.periods, periods)
      expectNoDifference(timeline.phases, [
        .period(testGamePeriodReference(number: 1), durationSeconds: 900),
        .breakTime(after: testGamePeriodReference(number: 1), durationSeconds: 120),
        .period(testGamePeriodReference(number: 2), durationSeconds: 600),
        .breakTime(after: testGamePeriodReference(number: 2), durationSeconds: 300),
        .period(testGamePeriodReference(number: 3), durationSeconds: 1200),
      ])
    }

    @Test(arguments: ["empty", "gap", "duplicatePosition", "duplicateID", "differentGame", "zeroPeriod", "negativePeriod", "negativeBreak", "finalBreak"])
    func malformedSchedulesAreRejected(reason: String) {
      var periods = testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 120)
      switch reason {
      case "empty": periods = []
      case "gap": periods[1].position = 2
      case "duplicatePosition": periods[1].position = 0
      case "duplicateID":
        periods[1] = GamePeriod(id: periods[0].id, gameID: UUID(3), position: 1, durationSeconds: 900)
      case "differentGame": periods[1].gameID = UUID(4)
      case "zeroPeriod": periods[0].durationSeconds = 0
      case "negativePeriod": periods[0].durationSeconds = -1
      case "negativeBreak": periods[0].breakAfterDurationSeconds = -1
      case "finalBreak": periods[1].breakAfterDurationSeconds = 120
      default: Issue.record("Unknown schedule fixture")
      }
      #expect(GameTimeline(periods: periods) == nil)
    }

    @Test
    func zeroBreakAndOmittedBreakHaveTheSameTimelineAndProgress() throws {
      let periods = testGamePeriods(gameID: UUID(3), count: 2)
      #expect(periods[0].breakAfterDurationSeconds == nil)
      var zeroPeriods = periods
      zeroPeriods[0].breakAfterDurationSeconds = 0
      let omitted = try #require(GameTimeline(periods: periods))
      let zero = try #require(GameTimeline(periods: zeroPeriods))
      expectNoDifference(zero.phases, omitted.phases)
      #expect(zero.phases.count == 2)
      var progress = GameProgress(
        phaseIndex: 0,
        countdown: GameCountdown(endsAt: Date(timeIntervalSince1970: 1000)),
        isAwaitingCentrePassConfirmation: false
      )
      progress.reconcile(in: zero, now: Date(timeIntervalSince1970: 2000))
      #expect(progress.phaseIndex == 1)
      expectNoDifference(progress.countdown, GameCountdown())
      #expect(progress.lateScoringPeriodNumber == 1)
      #expect(progress.isAwaitingCentrePassConfirmation)
    }

    @Test
    func mixedBreaksUseCompactIndexesForProgressAndAlarms() throws {
      let timeline = try #require(GameTimeline(periods:
        testGamePeriods(gameID: UUID(3), count: 3, breakDurations: [0, 120])))
      let boundary = Date(timeIntervalSince1970: 1000)
      var progress = GameProgress(
        phaseIndex: 0,
        countdown: GameCountdown(),
        isAwaitingCentrePassConfirmation: false
      )
      progress.complete(in: timeline, boundary: boundary)
      #expect(progress.phaseIndex == 1)
      #expect(timeline.phase(at: 1)?.associatedPeriod.id == testGamePeriodID(gameID: UUID(3), position: 1))
      progress.countdown.endsAt = boundary
      let alarms = ScheduledGameAlarm.plan(timeline: timeline, progress: progress.timing)
      #expect(alarms.map(\.phaseIndex) == [1, 2])
      #expect(alarms.map(\.date) == [boundary, boundary.addingTimeInterval(120)])
      progress.reconcile(in: timeline, now: boundary.addingTimeInterval(121))
      #expect(progress.phaseIndex == 3)
      #expect(progress.countdown == GameCountdown())
      #expect(progress.lateScoringPeriodNumber == 2)
    }

    @Test(arguments: ["first", "break", "waiting", "live", "final"])
    func activePrecedingAndScoringPeriodsHaveDistinctMeanings(stage: String) {
      let periods = testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 120)
      let index = stage == "first" ? 0 : stage == "break" ? 1 : 2
      let snapshot = GameSnapshot(
        game: Game(
          id: UUID(3),
          startedAt: .distantPast,
          teamAID: UUID(1),
          teamBID: UUID(2),
          isAwaitingCentrePassConfirmation: stage == "break" || stage == "waiting",
          lateScoringPeriodNumber: stage == "first" || stage == "live" ? nil : stage == "final" ? 2 : 1,
          currentPhaseIndex: index,
          elapsedSeconds: stage == "final" ? 900 : 0,
          timerEndsAt: stage == "break" || stage == "live" ? .distantFuture : nil
        ),
        goals: [],
        periods: periods,
        teamA: Team(id: UUID(1), name: "Ravens"),
        teamB: Team(id: UUID(2), name: "Swifts")
      )
      let state = ScoringFeature.State(snapshot: snapshot)
      let activeID: UUID? = stage == "break" ? nil : periods[index == 0 ? 0 : 1].id
      let precedingID: UUID? = stage == "first" ? nil : periods[0].id
      let scoringID: UUID? = stage == "first" ? nil : periods[stage == "live" || stage == "final" ? 1 : 0].id
      #expect(snapshot.activePlayingPeriod?.id == activeID)
      #expect(snapshot.precedingPeriod?.id == precedingID)
      #expect(snapshot.scoringPeriod?.id == scoringID)
      #expect(state.activePlayingPeriod?.id == activeID)
      #expect(state.precedingPeriod?.id == precedingID)
      #expect(state.scoringPeriod?.id == scoringID)
    }

    @Test
    func finalPeriodWithoutBreaksCompletesWithoutAdvancingOrRestarting() throws {
      let timeline = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 2)))
      let boundary = Date(timeIntervalSince1970: 1000)
      var progress = GameProgress(
        phaseIndex: 1,
        countdown: GameCountdown(endsAt: boundary),
        isAwaitingCentrePassConfirmation: false
      )
      progress.reconcile(in: timeline, now: boundary.addingTimeInterval(1000))
      #expect(progress.phaseIndex == 1)
      #expect(progress.isFinalPeriodComplete(in: timeline))
      #expect(progress.lateScoringPeriodNumber == 2)
      #expect(!progress.isAwaitingCentrePassConfirmation)
      #expect(ScheduledGameAlarm.plan(timeline: timeline, progress: progress.timing).isEmpty)
    }

    #if os(iOS)
      @Test
      func activityCarriesWaitingDeadlineAcrossRefreshAndEncoding() throws {
        let boundary = Date(timeIntervalSince1970: 1000)
        var content = GameActivityAttributes.ContentState(
          centrePassTeamID: UUID(1),
          elapsedSeconds: 20,
          phaseIndex: 1,
          phase: .breakTime(after: testGamePeriodReference(number: 1), durationSeconds: 120),
          teamAScore: 0,
          teamBScore: 0,
          timerEndsAt: boundary
        )
        #expect(content.breakTimerBoundary == boundary)
        content.phaseIndex = 2
        content.phase = .period(testGamePeriodReference(number: 2), durationSeconds: 900)
        content.elapsedSeconds = 0
        content.timerEndsAt = nil
        content.waitingSince = boundary
        let decoded = try JSONDecoder().decode(
          GameActivityAttributes.ContentState.self,
          from: JSONEncoder().encode(content)
        )
        #expect(decoded.breakTimerBoundary == boundary)
        #expect(decoded.remainingSeconds == 900)
        #expect(!decoded.canScoreGoal)
        content.waitingSince = nil
        #expect(content.breakTimerBoundary == nil)
        content.phase = .breakTime(after: testGamePeriodReference(number: 1), durationSeconds: 120)
        #expect(content.breakTimerBoundary == nil)
      }

      @Test
      func liveActivityEncodingPreservesPhaseIdentityAndUsesItsDuration() throws {
        let phase = GamePhase.breakTime(after: testGamePeriodReference(number: 1), durationSeconds: 120)
        let content = GameActivityAttributes.ContentState(
          centrePassTeamID: UUID(1),
          elapsedSeconds: 20,
          phaseIndex: 1,
          phase: phase,
          teamAScore: 0,
          teamBScore: 0,
          isAwaitingCentrePassConfirmation: true,
          lateScoringPeriodNumber: 1
        )
        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(GameActivityAttributes.ContentState.self, from: encoded)
        expectNoDifference(decoded, content)
        #expect(decoded.phase.associatedPeriod.id == testGamePeriodID(gameID: UUID(3), position: 0))
        #expect(decoded.remainingSeconds == 100)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["currentDurationSeconds"] == nil)
      }

    #endif

    @Test
    func invalidCursorDoesNotReportCompletionOrResolveAPeriod() throws {
      let timeline = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 1)))
      var progress = GameProgress(
        phaseIndex: -1,
        countdown: GameCountdown(),
        isAwaitingCentrePassConfirmation: false
      )
      #expect(!progress.isFinalPeriodComplete(in: timeline))
      progress.reconcile(in: timeline, now: .distantFuture)
      #expect(timeline.phase(at: -1) == nil)
      #expect(timeline.activePlayingPeriod(at: 1) == nil)
      #expect(timeline.precedingPeriod(at: 1) == nil)
      #expect(timeline.scoringPeriod(for: .completedPeriod(number: 2)) == nil)
    }

    @Test
    func storedZeroBreakIsCanonicalizedAndInvalidSchedulesCannotBeFetched() async throws {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      let periods = testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 0)
      try await database.write { db in
        try Team.insert {
          Team(id: UUID(1), name: "Ravens")
          Team(id: UUID(2), name: "Swifts")
        }.execute(db)
        try Game.insert {
          Game(id: UUID(3), startedAt: .distantPast, teamAID: UUID(1), teamBID: UUID(2))
        }.execute(db)
        try GamePeriod.insert { periods }.execute(db)
      }
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: UUID(3)) }
      #expect(snapshot.periods.allSatisfy { $0.breakAfterDurationSeconds == nil })
      #expect(snapshot.phases.count == 2)
      await #expect(throws: (any Error).self) {
        try await database.write { db in
          try GamePeriod.find(periods[0].id).update { $0.breakAfterDurationSeconds = #bind(0) }.execute(db)
        }
      }
      try await database.write { db in
        try GamePeriod.find(periods[1].id).update { $0.breakAfterDurationSeconds = #bind(120) }.execute(db)
      }
      await #expect(throws: (any Error).self) {
        try await database.read { try GameSnapshot.fetch($0, gameID: UUID(3)) }
      }
    }
  }
}
