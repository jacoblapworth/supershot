import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  struct GameTimelineTests {
    @Test
    func unorderedPeriodsProducePhasesWithStableIdentityAndIndividualDurations() throws {
      var periods = testGamePeriods(gameID: UUID(3), count: 3, breakDurations: [120, 300])
      periods[1].durationSeconds = 600
      periods[2].durationSeconds = 1_200
      let timeline = try #require(GameTimeline(periods: [periods[2], periods[0], periods[1]]))
      expectNoDifference(timeline.periods, periods)
      expectNoDifference(timeline.phases, [
        .period(testGamePeriodReference(number: 1), durationSeconds: 900),
        .breakTime(after: testGamePeriodReference(number: 1), durationSeconds: 120),
        .period(testGamePeriodReference(number: 2), durationSeconds: 600),
        .breakTime(after: testGamePeriodReference(number: 2), durationSeconds: 300),
        .period(testGamePeriodReference(number: 3), durationSeconds: 1_200),
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
      var progress = GameProgress(phaseIndex: 0,
        countdown: GameCountdown(endsAt: Date(timeIntervalSince1970: 1_000)),
        isAwaitingCentrePassConfirmation: false)
      progress.reconcile(in: zero, now: Date(timeIntervalSince1970: 2_000))
      #expect(progress.phaseIndex == 1)
      expectNoDifference(progress.countdown, GameCountdown())
      #expect(progress.lateScoringPeriodNumber == 1)
      #expect(progress.isAwaitingCentrePassConfirmation)
    }

    @Test
    func mixedBreaksUseCompactIndexesForProgressAndAlarms() throws {
      let timeline = try #require(GameTimeline(periods:
        testGamePeriods(gameID: UUID(3), count: 3, breakDurations: [0, 120])))
      let boundary = Date(timeIntervalSince1970: 1_000)
      var progress = GameProgress(phaseIndex: 0, countdown: GameCountdown(),
        isAwaitingCentrePassConfirmation: false)
      progress.complete(in: timeline, boundary: boundary)
      #expect(progress.phaseIndex == 1)
      #expect(timeline.phase(at: 1)?.associatedPeriod.id == testGamePeriodID(gameID: UUID(3), position: 1))
      progress.countdown.endsAt = boundary
      let alarms = ScheduledGameAlarm.plan(timeline: timeline, progress: progress)
      #expect(alarms.map(\.phaseIndex) == [1, 2])
      #expect(alarms.map(\.date) == [boundary, boundary.addingTimeInterval(120)])
      progress.reconcile(in: timeline, now: boundary.addingTimeInterval(121))
      #expect(progress.phaseIndex == 3)
      #expect(progress.countdown == GameCountdown())
      #expect(progress.lateScoringPeriodNumber == 2)
    }

    @Test(arguments: ["first", "break", "waiting", "live", "final"])
    func activePrecedingAndScoringPeriodsHaveDistinctMeanings(stage: String) throws {
      let periods = testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 120)
      let index = stage == "first" ? 0 : stage == "break" ? 1 : 2
      let snapshot = GameSnapshot(
        game: Game(id: UUID(3), startedAt: .distantPast, teamAID: UUID(1), teamBID: UUID(2),
          isAwaitingCentrePassConfirmation: stage == "break" || stage == "waiting",
          lateScoringPeriodNumber: stage == "first" || stage == "live" ? nil : stage == "final" ? 2 : 1,
          currentPhaseIndex: index, elapsedSeconds: stage == "final" ? 900 : 0,
          timerEndsAt: stage == "break" || stage == "live" ? .distantFuture : nil),
        goals: [], periods: periods,
        teamA: Team(id: UUID(1), name: "Ravens"), teamB: Team(id: UUID(2), name: "Swifts"))
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
      let boundary = Date(timeIntervalSince1970: 1_000)
      var progress = GameProgress(phaseIndex: 1, countdown: GameCountdown(endsAt: boundary),
        isAwaitingCentrePassConfirmation: false)
      progress.reconcile(in: timeline, now: boundary.addingTimeInterval(1_000))
      #expect(progress.phaseIndex == 1)
      #expect(progress.isFinalPeriodComplete(in: timeline))
      #expect(progress.lateScoringPeriodNumber == 2)
      #expect(!progress.isAwaitingCentrePassConfirmation)
      #expect(ScheduledGameAlarm.plan(timeline: timeline, progress: progress).isEmpty)
    }

    @Test
    func liveActivityEncodingPreservesPhaseIdentityAndUsesItsDuration() throws {
      let phase = GamePhase.breakTime(after: testGamePeriodReference(number: 1), durationSeconds: 120)
      let content = GameActivityAttributes.ContentState(centrePassTeamID: UUID(1), elapsedSeconds: 20,
        phaseIndex: 1, phase: phase, teamAScore: 0, teamBScore: 0,
        isAwaitingCentrePassConfirmation: true, lateScoringPeriodNumber: 1)
      let encoded = try JSONEncoder().encode(content)
      let decoded = try JSONDecoder().decode(GameActivityAttributes.ContentState.self, from: encoded)
      expectNoDifference(decoded, content)
      #expect(decoded.phase.associatedPeriod.id == testGamePeriodID(gameID: UUID(3), position: 0))
      #expect(decoded.remainingSeconds == 100)
      let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
      #expect(json["currentDurationSeconds"] == nil)
    }

    @Test
    func invalidCursorDoesNotReportCompletionOrResolveAPeriod() throws {
      let timeline = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 1)))
      var progress = GameProgress(phaseIndex: -1, countdown: GameCountdown(),
        isAwaitingCentrePassConfirmation: false)
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
