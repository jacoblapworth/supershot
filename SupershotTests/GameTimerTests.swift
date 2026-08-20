import Clocks
import ComposableArchitecture
import ConcurrencyExtras
import CustomDump
import Dependencies
import Foundation
import GRDB
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct GameTimerTests {
    @Test
    func timerMathUsesCeilingAndClampsInvalidValues() {
      let now = Date(timeIntervalSince1970: 1_000)

      expectNoDifference(
        GameTimerMath.elapsedSeconds(
          durationSeconds: 900,
          persistedElapsedSeconds: 0,
          timerEndsAt: now.addingTimeInterval(0.001),
          now: now
        ),
        899
      )
      expectNoDifference(
        GameTimerMath.elapsedSeconds(
          durationSeconds: 900,
          persistedElapsedSeconds: 0,
          timerEndsAt: now,
          now: now
        ),
        900
      )
      expectNoDifference(
        GameTimerMath.elapsedSeconds(
          durationSeconds: 900,
          persistedElapsedSeconds: 0,
          timerEndsAt: now.addingTimeInterval(10_000),
          now: now
        ),
        0
      )
      expectNoDifference(
        GameTimerMath.elapsedSeconds(
          durationSeconds: 900,
          persistedElapsedSeconds: 1_000,
          timerEndsAt: nil,
          now: now
        ),
        900
      )
      expectNoDifference(
        GameTimerMath.elapsedSeconds(
          durationSeconds: 900,
          persistedElapsedSeconds: -20,
          timerEndsAt: nil,
          now: now
        ),
        0
      )
      expectNoDifference(
        GameTimerMath.endDate(
          durationSeconds: 900,
          elapsedSeconds: 125,
          now: now
        ),
        Date(timeIntervalSince1970: 1_775)
      )
    }
    @Test
    func timerClientPersistsStartPauseResumeAndIgnoresStaleActions() async throws {
      let seedStore = Self.makeScoringStore()
      let database = seedStore.dependencies.defaultDatabase
      let currentDate = LockIsolated(Date(timeIntervalSince1970: 1_000))
      let events = LockIsolated<[TimerSystemEvent]>([])
      let client = GameTimerClient.live(system: Self.timerSystemClient(events: events))

      try await withDependencies {
        $0.date = DateGenerator { currentDate.value }
        $0.defaultDatabase = database
      } operation: {
        let started = try await client.startOrResume(UUID(3), 1, true)
        expectNoDifference(started.snapshot.game.elapsedSeconds, 0)
        expectNoDifference(
          started.snapshot.game.timerEndsAt,
          Date(timeIntervalSince1970: 1_900)
        )
        expectNoDifference(
          events.value,
          [
            .activity(Date(timeIntervalSince1970: 1_900)),
            .alarm(Date(timeIntervalSince1970: 1_900), requestsAuthorization: true),
          ]
        )

        events.setValue([])
        _ = try await client.startOrResume(UUID(3), 1, false)
        expectNoDifference(
          events.value,
          [.activity(Date(timeIntervalSince1970: 1_900))]
        )

        events.setValue([])
        let stalePause = try await client.pause(UUID(3), 2)
        expectNoDifference(
          stalePause.game.timerEndsAt,
          Date(timeIntervalSince1970: 1_900)
        )
        expectNoDifference(
          events.value,
          [.activity(Date(timeIntervalSince1970: 1_900))]
        )

        currentDate.setValue(Date(timeIntervalSince1970: 1_500))
        let relaunched = try await client.reconcile(UUID(3))
        expectNoDifference(relaunched.game.elapsedSeconds, 500)
        let relaunchedState = ScoringFeature.State(snapshot: relaunched)
        expectNoDifference(relaunchedState.elapsedSeconds, 500)
        expectNoDifference(relaunchedState.isTimerRunning, true)

        events.setValue([])
        let paused = try await client.pause(UUID(3), 1)
        expectNoDifference(paused.game.elapsedSeconds, 500)
        expectNoDifference(paused.game.timerEndsAt, nil)
        expectNoDifference(events.value, [.cancelAlarm, .activity(nil)])

        events.setValue([])
        let resumed = try await client.startOrResume(UUID(3), 1, false)
        expectNoDifference(
          resumed.snapshot.game.timerEndsAt,
          Date(timeIntervalSince1970: 1_900)
        )
        expectNoDifference(
          events.value,
          [
            .activity(Date(timeIntervalSince1970: 1_900)),
            .alarm(Date(timeIntervalSince1970: 1_900), requestsAuthorization: false),
          ]
        )
      }
    }

    @Test
    func timerClientSchedulesAlarmWhenBreakStarts() async throws {
      var state = Self.scoringState()
      state.clockPhase = .breakTime
      state.elapsedSeconds = 20
      state.firstBreakDurationSeconds = 120
      state.hasTimerStartedThisPeriod = true
      let seedStore = Self.makeScoringStore(state: state)
      let database = seedStore.dependencies.defaultDatabase
      let events = LockIsolated<[TimerSystemEvent]>([])
      let client = GameTimerClient.live(system: Self.timerSystemClient(events: events))

      let update = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.startOrResume(UUID(3), 1, false)
      }

      expectNoDifference(update.alarmAuthorizationDenied, false)
      expectNoDifference(
        update.snapshot.game.timerEndsAt,
        Date(timeIntervalSince1970: 1_100)
      )
      expectNoDifference(
        events.value,
        [
          .activity(Date(timeIntervalSince1970: 1_100)),
          .alarm(Date(timeIntervalSince1970: 1_100), requestsAuthorization: false),
        ]
      )
    }

    @Test
    func timerClientReconcilesQuarterAndBreakAcrossLargeTimeJumps() async throws {
      var state = Self.scoringState()
      state.firstBreakDurationSeconds = 120
      state.hasTimerStartedThisPeriod = true
      state.isTimerRunning = true
      state.timerEndsAt = Date(timeIntervalSince1970: 1_050)
      let seedStore = Self.makeScoringStore(state: state)
      let database = seedStore.dependencies.defaultDatabase
      let currentDate = LockIsolated(Date(timeIntervalSince1970: 1_100))
      let client = GameTimerClient.live(system: .noop)

      try await withDependencies {
        $0.date = DateGenerator { currentDate.value }
        $0.defaultDatabase = database
      } operation: {
        let duringBreak = try await client.reconcile(UUID(3))
        expectNoDifference(duringBreak.game.isInBreak, true)
        expectNoDifference(duringBreak.game.isAwaitingCentrePassConfirmation, true)
        expectNoDifference(duringBreak.game.elapsedSeconds, 50)
        expectNoDifference(
          duringBreak.game.timerEndsAt,
          Date(timeIntervalSince1970: 1_170)
        )

        currentDate.setValue(Date(timeIntervalSince1970: 1_300))
        let afterBreak = try await client.reconcile(UUID(3))
        expectNoDifference(afterBreak.game.isInBreak, true)
        expectNoDifference(afterBreak.game.elapsedSeconds, 120)
        expectNoDifference(afterBreak.game.timerEndsAt, nil)
      }
    }

    @Test
    func unavailableSystemPresentationsDoNotRollBackTimer() async throws {
      let seedStore = Self.makeScoringStore()
      let database = seedStore.dependencies.defaultDatabase
      let events = LockIsolated<[TimerSystemEvent]>([])
      let client = GameTimerClient.live(
        system: Self.timerSystemClient(events: events, alarmUnavailable: true)
      )

      let update = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.startOrResume(UUID(3), 1, true)
      }

      expectNoDifference(update.alarmAuthorizationDenied, true)
      expectNoDifference(
        update.snapshot.game.timerEndsAt,
        Date(timeIntervalSince1970: 1_900)
      )
      let storedGame = try await database.read { db in
        try Game.find(UUID(3)).fetchOne(db)
      }
      expectNoDifference(
        storedGame?.timerEndsAt,
        Date(timeIntervalSince1970: 1_900)
      )
    }

    @Test
    func alarmUnavailableExplanationAppearsOnlyOncePerScoringSession() async {
      let clock = TestClock()
      let events = LockIsolated<[TimerSystemEvent]>([])
      let gameTimer = GameTimerClient.live(
        system: Self.timerSystemClient(events: events, alarmUnavailable: true)
      )
      let store = Self.makeScoringStore(clock: clock, gameTimer: gameTimer)

      await store.send(.startTimerButtonTapped) {
        $0.hasTimerStartedThisPeriod = true
        $0.isTimerRunning = true
        $0.timerEndsAt = Date(timeIntervalSince1970: 1_900)
      }
      await store.receive {
        guard case .timerStartResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.alert = .alarmUnavailable
        $0.hasShownAlarmUnavailableAlert = true
      }
      await store.send(.alert(.presented(.dismissButtonTapped))) {
        $0.alert = nil
      }

      await store.send(.pauseTimerButtonTapped) {
        $0.isTimerRunning = false
        $0.timerEndsAt = nil
      }
      await store.receive {
        guard case .timerPauseResponse(.success) = $0 else { return false }
        return true
      }

      await store.send(.startTimerButtonTapped) {
        $0.isTimerRunning = true
        $0.timerEndsAt = Date(timeIntervalSince1970: 1_900)
      }
      await store.receive {
        guard case .timerStartResponse(.success) = $0 else { return false }
        return true
      }
      expectNoDifference(store.state.alert, nil)

      await store.send(.pauseTimerButtonTapped) {
        $0.isTimerRunning = false
        $0.timerEndsAt = nil
      }
      await store.receive {
        guard case .timerPauseResponse(.success) = $0 else { return false }
        return true
      }
      await store.finish()
    }

    private nonisolated static func timerSystemClient(
        events: LockIsolated<[TimerSystemEvent]>,
        alarmUnavailable: Bool = false
      ) -> GameTimerSystemClient {
        GameTimerSystemClient(
          cancelAlarm: { _ in
            events.withValue { $0.append(.cancelAlarm) }
          },
          endActivity: { _ in
            events.withValue { $0.append(.endActivity) }
          },
          scheduleAlarm: { snapshot, requestsAuthorization in
            events.withValue {
              $0.append(
                .alarm(
                  snapshot.game.timerEndsAt,
                  requestsAuthorization: requestsAuthorization
                )
              )
            }
            return alarmUnavailable
          },
          updateActivity: { snapshot, _ in
            events.withValue {
              $0.append(.activity(snapshot.game.timerEndsAt))
            }
          }
        )
      }


      private static func makeScoringStore(
        state: ScoringFeature.State = scoringState(),
        date: Date = Date(timeIntervalSince1970: 1_000),
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
                periodDurationSeconds: state.periodDurationSeconds,
                firstBreakDurationSeconds: state.firstBreakDurationSeconds,
                halfTimeDurationSeconds: state.halfTimeDurationSeconds,
                secondBreakDurationSeconds: state.secondBreakDurationSeconds,
                isInBreak: state.clockPhase == .breakTime,
                isAwaitingCentrePassConfirmation: state.isShowingLastCentrePassBanner,
                currentPeriod: state.period,
                elapsedSeconds: state.elapsedSeconds,
                hasTimerStartedCurrentPeriod: state.hasTimerStartedThisPeriod,
                timerEndsAt: state.timerEndsAt
              )
            }
            .execute(db)
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
          startedAt: Date(timeIntervalSince1970: 500),
          teamA: ScoringFeature.Team(
            id: UUID(1),
            bibColorHex: TeamColorPalette.blue,
            name: "Ravens"
          ),
          teamB: ScoringFeature.Team(
            id: UUID(2),
            bibColorHex: TeamColorPalette.red,
            name: "Swifts"
          )
        )
      }
  }
}


private nonisolated enum TimerSystemEvent: Equatable, Sendable {
  case activity(Date?)
  case alarm(Date?, requestsAuthorization: Bool)
  case cancelAlarm
  case endActivity
}
