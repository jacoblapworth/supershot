@testable import AlarmClient
import Clocks
import ComposableArchitecture
import ConcurrencyExtras
import CustomDump
@testable import Database
import Dependencies
import DependenciesTestSupport
import Foundation
@testable import GameCore
@testable import GameServices
@testable import GamesFeature
import GRDB
import OrderedCollections
import PermissionsFeature
@testable import ScoringFeature
@testable import SharedModels
import SQLiteData
@testable import Styleguide
@testable import SubscriptionClient
import SwiftUI
@testable import TeamsFeature
import Testing
import TestSupport
@testable import WidgetSupport
#if os(iOS)
  internal import AlarmKit
#endif

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
  }) struct GameTimerTests {
    @Test(arguments: [false, true])
    func manualBreakWaitsAcrossRecoveryThenStartsPausesResumesAndSkips(endsEarly: Bool) async throws {
      let seed = Self.makeScoringStore()
      let database = seed.dependencies.defaultDatabase
      let now = LockIsolated(Date(timeIntervalSince1970: 1000))
      let plans = LockIsolated<[[ScheduledGameAlarm]]>([])
      try await database.write { db in
        try Game.find(UUID(3)).update { $0.breakStartPolicy = #bind(BreakStartPolicy.manual) }.execute(db)
        try GamePeriod.find(testGamePeriodID(gameID: UUID(3), position: 0))
          .update { $0.breakAfterDurationSeconds = #bind(120) }.execute(db)
      }
      try await withDependencies {
        $0.defaultDatabase = database
        $0.date = DateGenerator { now.value }
        $0.proSubscription = .pro
        $0.alarmClient = AlarmClient(
          scheduleAlarm: { snapshot in
            plans.withValue { $0.append(ScheduledGameAlarm.plan(timeline: snapshot.timeline, progress: snapshot.game.timing)) }
            return false
          }, updateActivity: { _, _ in }, cancelAlarm: { _, _ in }, endActivity: { _ in }
        )
      } operation: {
        let client = GameTimerClient.live
        _ = try await client.startOrResume(UUID(3), 0)
        #expect(plans.value.first?.map(\.phaseIndex) == [0])
        now.setValue(Date(timeIntervalSince1970: endsEarly ? 1050 : 5000))
        let waiting = endsEarly
          ? try await client.skip(UUID(3), 0)
          : try await client.reconcile(UUID(3))
        #expect(waiting.game.currentPhaseIndex == 1)
        #expect(waiting.game.countdown == GameCountdown())
        #expect(waiting.game.isAwaitingCentrePassConfirmation)
        #expect(waiting.game.lateScoringPeriodNumber == 1)
        #expect(plans.value.count == 1)
        let stale = try await client.startOrResume(UUID(3), 0)
        #expect(stale.snapshot.game.timerEndsAt == nil)
        now.setValue(Date(timeIntervalSince1970: 10000))
        let recovered = try await client.reconcile(UUID(3))
        #expect(recovered.game.breakStartPolicy == .manual)
        #expect(recovered.game.countdown == GameCountdown())
        let ui = ScoringFeature.State(snapshot: recovered)
        #expect(ui.clockPhase == .breakTime)
        #expect(ui.timeRemainingSeconds == 120)
        #expect(ui.scoringPeriod?.number == 1)
        let started = try await client.startOrResume(UUID(3), 1)
        #expect(started.snapshot.game.timerEndsAt == Date(timeIntervalSince1970: 10120))
        #expect(started.snapshot.game.isAwaitingCentrePassConfirmation)
        #expect(plans.value.last?.map(\.phaseIndex) == [1])
        now.setValue(Date(timeIntervalSince1970: 10030))
        let paused = try await client.pause(UUID(3), 1)
        #expect(paused.game.elapsedSeconds == 30)
        #expect(paused.game.timerEndsAt == nil)
        try await database.write { db in
          try Game.find(UUID(3)).update { $0.isAwaitingCentrePassConfirmation = false }.execute(db)
        }
        let corrected = try await client.setRemainingTime(UUID(3), 1, 75)
        #expect(corrected.game.elapsedSeconds == 45)
        now.setValue(Date(timeIntervalSince1970: 11000))
        let resumed = try await client.startOrResume(UUID(3), 1)
        #expect(resumed.snapshot.game.timerEndsAt == Date(timeIntervalSince1970: 11075))
        let next = try await client.skip(UUID(3), 1)
        #expect(next.game.currentPhaseIndex == 2)
        #expect(next.game.countdown == GameCountdown())
      }
    }

    @Test
    func timerMathUsesCeilingAndClampsInvalidValues() {
      let now = Date(timeIntervalSince1970: 1000)

      expectNoDifference(
        GameTimerClient.elapsedSeconds(
          durationSeconds: 900,
          persistedElapsedSeconds: 0,
          timerEndsAt: now.addingTimeInterval(0.001),
          now: now
        ),
        899
      )
      expectNoDifference(
        GameTimerClient.elapsedSeconds(
          durationSeconds: 900,
          persistedElapsedSeconds: 0,
          timerEndsAt: now,
          now: now
        ),
        900
      )
      expectNoDifference(
        GameTimerClient.elapsedSeconds(
          durationSeconds: 900,
          persistedElapsedSeconds: 0,
          timerEndsAt: now.addingTimeInterval(10000),
          now: now
        ),
        0
      )
      expectNoDifference(
        GameTimerClient.elapsedSeconds(
          durationSeconds: 900,
          persistedElapsedSeconds: 1000,
          timerEndsAt: nil,
          now: now
        ),
        900
      )
      expectNoDifference(
        GameTimerClient.elapsedSeconds(
          durationSeconds: 900,
          persistedElapsedSeconds: -20,
          timerEndsAt: nil,
          now: now
        ),
        0
      )
      expectNoDifference(
        GameTimerClient.endDate(
          durationSeconds: 900,
          elapsedSeconds: 125,
          now: now
        ),
        Date(timeIntervalSince1970: 1775)
      )
    }

    @Test(arguments: [1169.999, 1170, 1170.001])
    func breakBoundaryReconciliationStopsAtPausedPeriod(timestamp: Double) throws {
      let timeline = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: 120)))
      var progress = GameProgress(phaseIndex: 0,
                                  countdown: GameCountdown(endsAt: Date(timeIntervalSince1970: 1050)),
                                  isAwaitingCentrePassConfirmation: false)
      progress.reconcile(in: timeline, now: Date(timeIntervalSince1970: timestamp))
      #expect(progress.phaseIndex == (timestamp < 1170 ? 1 : 2))
      #expect(progress.countdown.elapsedSeconds == (timestamp < 1170 ? 119 : 0))
      #expect(progress.countdown.isRunning == (timestamp < 1170))
      #expect(progress.isAwaitingCentrePassConfirmation)
    }

    @Test
    func omittedBreakDoesNotAutomaticallyStartNextPeriod() throws {
      let timeline = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 2)))
      var progress = GameProgress(phaseIndex: 0, countdown: GameCountdown(),
                                  isAwaitingCentrePassConfirmation: false)
      progress.complete(in: timeline, boundary: Date(timeIntervalSince1970: 1000))
      #expect(progress.phaseIndex == 1)
      #expect(progress.countdown == GameCountdown())
      #expect(progress.isAwaitingCentrePassConfirmation)
      #if os(iOS)
        let state = GameActivityAttributes.ContentState(
          centrePassTeamID: UUID(1), elapsedSeconds: 0,
          phaseIndex: 1, phase: timeline.phases[1], teamAScore: 0, teamBScore: 0
        )
        #expect(!state.isInBreak)
        #expect(state.period == 2)
      #endif
    }

    @Test
    func alarmPlanIncludesFollowingBreakAndOmitsZeroBreak() throws {
      let end = Date(timeIntervalSince1970: 1050)
      for duration in [0, 120] {
        let timeline = try #require(GameTimeline(periods: testGamePeriods(gameID: UUID(3), count: 2, breakDurationSeconds: duration)))
        let progress = GameProgress(phaseIndex: 0, countdown: GameCountdown(endsAt: end),
                                    isAwaitingCentrePassConfirmation: false)
        let plan = ScheduledGameAlarm.plan(timeline: timeline, progress: progress.timing)
        #expect(plan.count == (duration > 0 ? 2 : 1))
        #expect(plan.first?.date == end)
        #expect(plan.first?.phaseIndex == 0)
        if duration > 0 {
          #expect(plan.last?.date == end.addingTimeInterval(120))
          #expect(plan.last?.phase == .breakTime(after: testGamePeriodReference(number: 1), durationSeconds: 120))
        }
        #expect(ScheduledGameAlarm.plan(timeline: timeline,
                                        progress: GameTimingState(phaseIndex: 0, countdown: GameCountdown())).isEmpty)
      }
    }

    @Test
    func delayedStartResponseCannotOverwritePause() async throws {
      let responseClock = TestClock()
      let timerClock = TestClock()
      let store = Self.makeScoringStore(clock: timerClock)
      let database = store.dependencies.defaultDatabase
      let snapshot = try await database.read { try GameSnapshot.fetch($0, gameID: UUID(3)) }
      store.dependencies.gameTimer.startOrResume = { _, _ in
        try await responseClock.sleep(for: .seconds(1))
        var game = snapshot.game
        game.timerEndsAt = Date(timeIntervalSince1970: 1900)
        return GameTimerUpdate(snapshot: GameSnapshot(game: game, goals: snapshot.goals,
                                                      periods: snapshot.periods, teamA: snapshot.teamA, teamB: snapshot.teamB))
      }
      store.dependencies.gameTimer.pause = { _, _ in snapshot }
      await store.send(.startTimerButtonTapped) {
        $0.timerEndsAt = Date(timeIntervalSince1970: 1900)
      }
      await store.send(.pauseTimerButtonTapped) {
        $0.timerEndsAt = nil
        $0.isTimerOperationPending = true
      }
      await store.receive {
        if case .timerPauseResponse = $0 {
          true
        } else {
          false
        }
      } assert: {
        $0.isTimerOperationPending = false
      }
      await responseClock.advance(by: .seconds(1))
      #expect(!store.state.isTimerRunning)
      await store.finish()
    }

    @Test
    func timeEditorCoordinatesSheetsAndRestoresControlsDetent() async {
      let store = Self.makeScoringStore()
      let originalDetent = store.state.presentationDetent
      await Self.openTimeEditor(store)
      await store.send(.timeInput(.presented(.cancelButtonTapped)))
      await store.receive(\.timeInput.presented.delegate.cancelled) { $0.timeInput = nil }
      await store.send(.timeInputSheetDidDismiss) {
        $0.editedPhaseIndex = nil
        $0.controlsPresentation = .shown
      }
      #expect(store.state.presentationDetent == originalDetent)
      #expect(store.state.elapsedSeconds == 0)
    }

    @Test
    func failedClockSaveRetainsDraftForRetry() async {
      let store = Self.makeScoringStore()
      store.dependencies.gameTimer.setRemainingTime = { _, _, _ in
        throw CocoaError(.fileWriteNoPermission)
      }
      await Self.openTimeEditor(store)
      await store.send(.timeInput(.presented(.delegate(.committed(120))))) {
        $0.timeInput?.isSaving = true
      }
      await store.receive(\.timeCorrectionResponse.failure) {
        $0.timeInput?.isSaving = false
        $0.timeInput?.errorMessage = CocoaError(.fileWriteNoPermission).localizedDescription
      }
      #expect(store.state.elapsedSeconds == 0)
      await store.send(.timeInput(.dismiss)) { $0.timeInput = nil }
      await store.send(.timeInputSheetDidDismiss) {
        $0.editedPhaseIndex = nil
        $0.controlsPresentation = .shown
      }
    }

    @Test(arguments: [false, true])
    func clockCorrectionCanBeSavedForQuarterOrBreak(isBreak: Bool) async throws {
      var state = Self.scoringState()
      state.periods = testGamePeriods(gameID: UUID(3), breakDurationSeconds: 120)
      state.currentPhaseIndex = isBreak ? 1 : 0
      let store = Self.makeScoringStore(state: state)
      let database = store.dependencies.defaultDatabase
      let events = LockIsolated<[TimerSystemEvent]>([])
      store.dependencies.alarmClient = Self.alarmClient(events: events)
      store.dependencies.proSubscription = .pro
      await Self.openTimeEditor(store)
      await store.send(.timeInput(.presented(.delegate(.committed(60))))) {
        $0.timeInput?.isSaving = true
      }
      await store.receive(\.timeCorrectionResponse.success) {
        $0.elapsedSeconds = state.currentDurationSeconds - 60
        $0.timeInput = nil
      }
      await store.send(.timeInputSheetDidDismiss) {
        $0.editedPhaseIndex = nil
        $0.controlsPresentation = .shown
      }
      let saved = try await database.read { try GameSnapshot.fetch($0, gameID: UUID(3)) }
      #expect(saved.game.elapsedSeconds == state.currentDurationSeconds - 60)
      #expect(!store.state.isTimerRunning)
      #expect(events.value == [.cancelAlarm, .activity(nil)])
    }

    @Test func timeEditorCannotOpenForRunningCompleteOrPendingClock() async {
      for condition in 0 ..< 4 {
        var state = Self.scoringState()
        switch condition {
        case 0: state.timerEndsAt = Date(timeIntervalSince1970: 1900)
        case 1: state.elapsedSeconds = state.currentDurationSeconds
        case 2: state.isTimerOperationPending = true
        default: state.isShowingLastCentrePassBanner = true
        }
        let store = Self.makeScoringStore(state: state)
        await store.send(.editTimeButtonTapped)
        #expect(store.state.timeInput == nil)
      }
    }

    @Test
    func clockCorrectionPersistsAndRejectsInvalidOrRunningEdits() async throws {
      let store = Self.makeScoringStore()
      let database = store.dependencies.defaultDatabase
      let events = LockIsolated<[TimerSystemEvent]>([])
      try await withDependencies {
        $0.defaultDatabase = database
        $0.date.now = Date(timeIntervalSince1970: 1000)
        $0.proSubscription = .pro
        $0.alarmClient = Self.alarmClient(events: events)
      } operation: {
        let client = GameTimerClient.live
        let corrected = try await client.setRemainingTime(UUID(3), 0, 125)
        #expect(corrected.game.elapsedSeconds == 775)
        #expect(corrected.game.timerEndsAt == nil)
        #expect(events.value == [.cancelAlarm, .activity(nil)])
        let saved = try await database.read { try GameSnapshot.fetch($0, gameID: UUID(3)) }
        #expect(saved.game.elapsedSeconds == 775)
        for (phase, seconds) in [(1, 120), (0, 0), (0, 901)] {
          await #expect(throws: (any Error).self) {
            try await client.setRemainingTime(UUID(3), phase, seconds)
          }
        }
        let started = try await client.startOrResume(UUID(3), 0)
        #expect(started.snapshot.game.timerEndsAt == Date(timeIntervalSince1970: 1125))
        await #expect(throws: (any Error).self) {
          try await client.setRemainingTime(UUID(3), 0, 120)
        }
      }
    }

    @Test
    func freeAccessPersistsTimersWithoutCreatingPremiumPresentations() async throws {
      let seedStore = Self.makeScoringStore()
      let database = seedStore.dependencies.defaultDatabase
      let events = LockIsolated<[TimerSystemEvent]>([])
      let client = GameTimerClient.live

      let update = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1000)
        $0.defaultDatabase = database
        $0.proSubscription = .free
        $0.alarmClient = Self.alarmClient(events: events)
      } operation: {
        try await client.startOrResume(UUID(3), 0)
      }

      expectNoDifference(
        update.snapshot.game.timerEndsAt,
        Date(timeIntervalSince1970: 1900)
      )
      expectNoDifference(update.alarmSchedulingFailed, false)
      expectNoDifference(events.value, [.cancelAlarm, .endActivity])
    }

    @Test
    func timerClientPersistsStartPauseResumeAndIgnoresStaleActions() async throws {
      let seedStore = Self.makeScoringStore()
      let database = seedStore.dependencies.defaultDatabase
      let currentDate = LockIsolated(Date(timeIntervalSince1970: 1000))
      let events = LockIsolated<[TimerSystemEvent]>([])

      try await withDependencies {
        $0.date = DateGenerator { currentDate.value }
        $0.defaultDatabase = database
        $0.alarmClient = Self.alarmClient(events: events)
      } operation: {
        @Dependency(\.gameTimer) var client
        let started = try await client.startOrResume(UUID(3), 0)
        expectNoDifference(started.snapshot.game.elapsedSeconds, 0)
        expectNoDifference(
          started.snapshot.game.timerEndsAt,
          Date(timeIntervalSince1970: 1900)
        )
        expectNoDifference(
          events.value,
          [
            .activity(Date(timeIntervalSince1970: 1900)),
            .alarm(Date(timeIntervalSince1970: 1900)),
          ]
        )

        events.setValue([])
        _ = try await client.startOrResume(UUID(3), 0)
        expectNoDifference(
          events.value,
          [.activity(Date(timeIntervalSince1970: 1900))]
        )

        events.setValue([])
        let stalePause = try await client.pause(UUID(3), 1)
        expectNoDifference(
          stalePause.game.timerEndsAt,
          Date(timeIntervalSince1970: 1900)
        )
        expectNoDifference(
          events.value,
          [.activity(Date(timeIntervalSince1970: 1900))]
        )

        currentDate.setValue(Date(timeIntervalSince1970: 1500))
        let relaunched = try await client.reconcile(UUID(3))
        expectNoDifference(relaunched.game.elapsedSeconds, 500)
        let relaunchedState = ScoringFeature.State(snapshot: relaunched)
        expectNoDifference(relaunchedState.elapsedSeconds, 500)
        expectNoDifference(relaunchedState.isTimerRunning, true)

        events.setValue([])
        let paused = try await client.pause(UUID(3), 0)
        expectNoDifference(paused.game.elapsedSeconds, 500)
        expectNoDifference(paused.game.timerEndsAt, nil)
        expectNoDifference(events.value, [.cancelAlarm, .activity(nil)])

        events.setValue([])
        let resumed = try await client.startOrResume(UUID(3), 0)
        expectNoDifference(
          resumed.snapshot.game.timerEndsAt,
          Date(timeIntervalSince1970: 1900)
        )
        expectNoDifference(
          events.value,
          [
            .activity(Date(timeIntervalSince1970: 1900)),
            .alarm(Date(timeIntervalSince1970: 1900)),
          ]
        )
      }
    }

    @Test
    func timerClientSchedulesAlarmWhenBreakStarts() async throws {
      var state = Self.scoringState()
      state.currentPhaseIndex = 1
      state.elapsedSeconds = 20
      state.periods[0].breakAfterDurationSeconds = 120
      let seedStore = Self.makeScoringStore(state: state)
      let database = seedStore.dependencies.defaultDatabase
      let events = LockIsolated<[TimerSystemEvent]>([])

      let update = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1000)
        $0.defaultDatabase = database
        $0.alarmClient = Self.alarmClient(events: events)
      } operation: {
        @Dependency(\.gameTimer) var client
        return try await client.startOrResume(UUID(3), 1)
      }

      expectNoDifference(update.alarmSchedulingFailed, false)
      expectNoDifference(
        update.snapshot.game.timerEndsAt,
        Date(timeIntervalSince1970: 1100)
      )
      expectNoDifference(
        events.value,
        [
          .activity(Date(timeIntervalSince1970: 1100)),
          .alarm(Date(timeIntervalSince1970: 1100)),
        ]
      )
    }

    @Test
    func timerClientReconcilesWithoutDismissingPhaseAlarms() async throws {
      var state = Self.scoringState()
      state.periods[0].breakAfterDurationSeconds = 120
      state.timerEndsAt = Date(timeIntervalSince1970: 1050)
      let seedStore = Self.makeScoringStore(state: state)
      let database = seedStore.dependencies.defaultDatabase
      let currentDate = LockIsolated(Date(timeIntervalSince1970: 1100))
      let events = LockIsolated<[TimerSystemEvent]>([])

      try await withDependencies {
        $0.date = DateGenerator { currentDate.value }
        $0.defaultDatabase = database
        $0.alarmClient = Self.alarmClient(events: events)
      } operation: {
        @Dependency(\.gameTimer) var client
        let duringBreak = try await client.reconcile(UUID(3))
        expectNoDifference(duringBreak.game.currentPhaseIndex, 1)
        expectNoDifference(duringBreak.game.isAwaitingCentrePassConfirmation, true)
        expectNoDifference(duringBreak.game.elapsedSeconds, 50)
        expectNoDifference(
          duringBreak.game.timerEndsAt,
          Date(timeIntervalSince1970: 1170)
        )
        expectNoDifference(
          events.value,
          [.activity(Date(timeIntervalSince1970: 1170))]
        )

        events.setValue([])
        currentDate.setValue(Date(timeIntervalSince1970: 1300))
        let afterBreak = try await client.reconcile(UUID(3))
        expectNoDifference(afterBreak.game.currentPhaseIndex, 2)
        expectNoDifference(afterBreak.game.elapsedSeconds, 0)
        expectNoDifference(afterBreak.game.timerEndsAt, nil)
        expectNoDifference(events.value, [.activity(nil)])
      }
    }

    @Test(arguments: [nil, 1, 2] as [Int?])
    func pauseAtExpiredBreakPersistsReconciledProgress(expectedPhaseIndex: Int?) async throws {
      var state = Self.scoringState()
      state.currentPhaseIndex = 1
      state.periods[0].breakAfterDurationSeconds = 120
      state.isShowingLastCentrePassBanner = true
      state.timerEndsAt = Date(timeIntervalSince1970: 1000)
      let seedStore = Self.makeScoringStore(state: state)
      let database = seedStore.dependencies.defaultDatabase

      try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1000)
        $0.defaultDatabase = database
      } operation: {
        let paused = try await GameTimerClient.live.pause(UUID(3), expectedPhaseIndex)
        let stored = try await database.read { try GameSnapshot.fetch($0, gameID: UUID(3)) }
        #expect(paused.game.currentPhaseIndex == 2)
        #expect(paused.game.timerEndsAt == nil)
        #expect(paused.game.elapsedSeconds == 0)
        #expect(paused.game.isAwaitingCentrePassConfirmation)
        expectNoDifference(stored.game, paused.game)
      }
    }

    @Test
    func unavailableSystemPresentationsDoNotRollBackTimer() async throws {
      let seedStore = Self.makeScoringStore()
      let database = seedStore.dependencies.defaultDatabase
      let events = LockIsolated<[TimerSystemEvent]>([])

      let update = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1000)
        $0.defaultDatabase = database
        $0.alarmClient = Self.alarmClient(events: events, alarmUnavailable: true)
      } operation: {
        @Dependency(\.gameTimer) var client
        return try await client.startOrResume(UUID(3), 0)
      }

      expectNoDifference(update.alarmSchedulingFailed, true)
      expectNoDifference(
        update.snapshot.game.timerEndsAt,
        Date(timeIntervalSince1970: 1900)
      )
      let storedGame = try await database.read { db in
        try Game.find(UUID(3)).fetchOne(db)
      }
      expectNoDifference(
        storedGame?.timerEndsAt,
        Date(timeIntervalSince1970: 1900)
      )
    }

    @Test
    func alarmUnavailableExplanationAppearsOnlyOncePerScoringSession() async {
      let clock = TestClock()
      let events = LockIsolated<[TimerSystemEvent]>([])
      let store = Self.makeScoringStore(clock: clock)
      store.dependencies.alarmClient = Self.alarmClient(events: events, alarmUnavailable: true)

      await store.send(.startTimerButtonTapped) {
        $0.timerEndsAt = Date(timeIntervalSince1970: 1900)
      }
      await store.receive {
        guard case .timerStartResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.alert = .alarmSchedulingFailed
        $0.hasShownAlarmSchedulingFailureAlert = true
      }
      await store.send(.alert(.presented(.dismissButtonTapped))) {
        $0.alert = nil
      }

      await store.send(.pauseTimerButtonTapped) {
        $0.timerEndsAt = nil
        $0.isTimerOperationPending = true
      }
      await store.receive {
        guard case .timerPauseResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.isTimerOperationPending = false
      }

      await store.send(.startTimerButtonTapped) {
        $0.timerEndsAt = Date(timeIntervalSince1970: 1900)
      }
      await store.receive {
        guard case .timerStartResponse(.success) = $0 else { return false }
        return true
      }
      expectNoDifference(store.state.alert, nil)

      await store.send(.pauseTimerButtonTapped) {
        $0.timerEndsAt = nil
        $0.isTimerOperationPending = true
      }
      await store.receive {
        guard case .timerPauseResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.isTimerOperationPending = false
      }
      await store.finish()
    }

    @Test(arguments: [false, true])
    func enablingAlarmsSchedulesOnlyRunningGames(isRunning: Bool) async {
      var state = Self.scoringState()
      state.alarms.access = .pro
      if isRunning {
        state.timerEndsAt = Date(timeIntervalSince1970: 1900)
      }
      let events = LockIsolated<[TimerSystemEvent]>([])
      let store = Self.makeScoringStore(state: state)
      store.dependencies.alarmAuthorization.request = { .authorized }
      store.dependencies.alarmClient = Self.alarmClient(events: events)
      await store.send(.alarms(.enableButtonTapped)) { $0.alarms.isRequesting = true }
      await store.receive(\.alarms.authorizationResponse) {
        $0.alarms.isRequesting = false
        $0.alarms.authorization = .authorized
      }
      await store.receive {
        if case .alarms(.delegate(.authorized)) = $0 {
          true
        } else {
          false
        }
      }
      await store.receive(\.alarmScheduleResponse)
      await store.finish()
      #expect(events.value.contains {
        if case .alarm = $0 {
          return true
        }; return false
      } == isRunning)
    }

    @Test
    func scoringRoutesProPromotionThroughBothTabs() async {
      var scoring = Self.scoringState()
      scoring.alarms.access = .free
      var games = GamesFeature.State()
      games.path.append(.scoring(scoring))
      let gamesStore = TestStore(initialState: games) { GamesFeature() }
      gamesStore.exhaustivity = .off(showSkippedAssertions: false)
      await gamesStore.send(.path(.element(id: games.path.ids[0], action: .scoring(.alarms(.enableButtonTapped)))))
      await gamesStore.receive(\.path)
      #if os(iOS)
        #expect(gamesStore.state.path[0].scoring?.controlsPresentation == .dismissingForPaywall)
        await gamesStore.send(.path(.element(id: games.path.ids[0], action: .scoring(.controlsSheetDidDismiss))))
      #else
        #expect(gamesStore.state.path[0].scoring?.controlsPresentation == .hiddenForPaywall)
      #endif
      await gamesStore.receive(\.delegate)
      var teams = TeamsFeature.State()
      teams.path.append(.scoring(scoring))
      let teamsStore = TestStore(initialState: teams) { TeamsFeature() }
      teamsStore.exhaustivity = .off(showSkippedAssertions: false)
      await teamsStore.send(.path(.element(id: teams.path.ids[0], action: .scoring(.alarms(.enableButtonTapped)))))
      await teamsStore.receive(\.path)
      #if os(iOS)
        #expect(teamsStore.state.path[0].scoring?.controlsPresentation == .dismissingForPaywall)
        await teamsStore.send(.path(.element(id: teams.path.ids[0], action: .scoring(.controlsSheetDidDismiss))))
      #else
        #expect(teamsStore.state.path[0].scoring?.controlsPresentation == .hiddenForPaywall)
      #endif
      await teamsStore.receive(\.delegate)
      await teamsStore.send(.path(.element(id: teams.path.ids[0], action: .scoring(.proPaywallDidDismiss))))
      #expect(teamsStore.state.path[0].scoring?.controlsPresentation == .shown)
    }

    private static func openTimeEditor(_ store: TestStore<ScoringFeature.State, ScoringFeature.Action>) async {
      let phaseIndex = store.state.currentPhaseIndex
      let duration = store.state.currentDurationSeconds
      let remaining = store.state.timeRemainingSeconds
      #if os(macOS)
        await store.send(.editTimeButtonTapped) {
          $0.editedPhaseIndex = phaseIndex
          $0.controlsPresentation = .hiddenForTimeInput
          $0.timeInput = .init(title: "Edit remaining time", totalSeconds: remaining,
                               allowedSeconds: 1 ... duration, selectedUnit: .seconds)
        }
      #else
        await store.send(.editTimeButtonTapped) {
          $0.editedPhaseIndex = phaseIndex
          $0.controlsPresentation = .dismissingForTimeInput
        }
        #expect(store.state.timeInput == nil)
        await store.send(.controlsSheetDidDismiss) {
          $0.controlsPresentation = .hiddenForTimeInput
          $0.timeInput = .init(title: "Edit remaining time", totalSeconds: remaining,
                               allowedSeconds: 1 ... duration, selectedUnit: .seconds)
        }
      #endif
    }

    private nonisolated static func alarmClient(
      events: LockIsolated<[TimerSystemEvent]>,
      alarmUnavailable: Bool = false
    ) -> AlarmClient {
      AlarmClient(
        scheduleAlarm: { snapshot in
          events.withValue {
            $0.append(
              .alarm(
                snapshot.game.timerEndsAt
              )
            )
          }
          return alarmUnavailable
        },
        updateActivity: { snapshot, _ in
          events.withValue {
            $0.append(.activity(snapshot.game.timerEndsAt))
          }
        },
        cancelAlarm: { _, _ in
          events.withValue { $0.append(.cancelAlarm) }
        },
        endActivity: { _ in
          events.withValue { $0.append(.endActivity) }
        }
      )
    }

    private static func makeScoringStore(
      state: ScoringFeature.State = scoringState(),
      date: Date = Date(timeIntervalSince1970: 1000),
      clock: TestClock<Duration>? = nil,
      dismiss: DismissEffect? = nil,
      gameTimer: GameTimerClient? = nil
    ) -> TestStoreOf<ScoringFeature> {
      let clockStart = clock?.now
      return TestStore(initialState: state) {
        ScoringFeature()
      } withDependencies: {
        if let clock, let clockStart {
          $0.date = DateGenerator {
            let components = clockStart.duration(to: clock.now).components
            let seconds = Double(components.seconds)
              + Double(components.attoseconds) / 1_000_000_000_000_000_000
            return date.addingTimeInterval(seconds)
          }
        } else {
          $0.date.now = date
        }
        $0.uuid = .incrementing
        try! $0.bootstrapDatabase()
        try! clearDatabase($0.defaultDatabase)
        try! $0.defaultDatabase.write { db in
          try Team.insert {
            Team(id: UUID(1), name: "Ravens")
            Team(id: UUID(2), name: "Swifts")
          }
          .execute(db)

          try Game.insert {
            Game(
              id: UUID(3),
              startedAt: state.startedAt,
              endedAt: nil,
              teamAID: UUID(1),
              teamBID: UUID(2),
              centrePassTeamID: state.centrePassTeamID,
              isAwaitingCentrePassConfirmation: state.isShowingLastCentrePassBanner,
              currentPhaseIndex: state.currentPhaseIndex,
              elapsedSeconds: state.elapsedSeconds,
              timerEndsAt: state.timerEndsAt
            )
          }
          .execute(db)
          try GamePeriod.insert { state.periods }.execute(db)
        }
        if let clock {
          $0.continuousClock = clock
        }
        if let dismiss {
          $0.dismiss = dismiss
        }
        if let gameTimer {
          $0.gameTimer = gameTimer
        }
      }
    }

    private nonisolated static func scoringState() -> ScoringFeature.State {
      ScoringFeature.State(
        centrePassTeamID: UUID(1),
        gameID: UUID(3),
        periods: testGamePeriods(gameID: UUID(3)),
        startedAt: Date(timeIntervalSince1970: 500),
        teamA: ScoringFeature.Team(
          id: UUID(1),
          bibColor: ColorPalette.blue,
          name: "Ravens"
        ),
        teamB: ScoringFeature.Team(
          id: UUID(2),
          bibColor: ColorPalette.red,
          name: "Swifts"
        )
      )
    }
  }
}

private nonisolated enum TimerSystemEvent: Equatable, Sendable {
  case activity(Date?)
  case alarm(Date?)
  case cancelAlarm
  case endActivity
}
