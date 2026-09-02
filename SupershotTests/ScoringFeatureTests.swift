import ComposableArchitecture
import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import Supershot
import DependenciesTestSupport

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
  }) struct ScoringFeatureTests {
    @Test
    func gameTimelineIsFourQuartersWithBreaksBetweenThem() {
      expectNoDifference(
        gamePhases(for: Self.periods()),
        [
          .period(number: 1, durationSeconds: 900),
          .breakTime(afterPeriod: 1, durationSeconds: 120),
          .period(number: 2, durationSeconds: 900),
          .breakTime(afterPeriod: 2, durationSeconds: 300),
          .period(number: 3, durationSeconds: 900),
          .breakTime(afterPeriod: 3, durationSeconds: 120),
          .period(number: 4, durationSeconds: 900),
        ]
      )
    }

    @Test
    func twoPeriodGameUsesOneBreakAndFinishesAfterSecondPeriod() async throws {
      var game = Self.game()
      game.currentPhaseIndex = 2
      let periods = testGamePeriods(
        gameID: game.id,
        count: 2,
        durationSeconds: 1_800,
        breakDurationSeconds: 600
      )
      let database = try await Self.seed(game, periods: periods)
      let client = GameTimerClient.live

      expectNoDifference(
        gamePhases(for: periods),
        [
          .period(number: 1, durationSeconds: 1_800),
          .breakTime(afterPeriod: 1, durationSeconds: 600),
          .period(number: 2, durationSeconds: 1_800),
        ]
      )

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.skip(game.id, 2)
      }

      expectNoDifference(snapshot.game.currentPhaseIndex, 2)
      expectNoDifference(snapshot.game.elapsedSeconds, 1_800)
      expectNoDifference(snapshot.game.timerEndsAt, nil)
      expectNoDifference(ScoringFeature.State(snapshot: snapshot).canFinishGame, true)
    }

    @Test
    func skippingQuarterStartsItsBreakAndRequestsLastCentrePass() async throws {
      let database = try await Self.seed(Self.game())
      let client = GameTimerClient.live

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.skip(UUID(3), 0)
      }

      expectNoDifference(snapshot.game.currentPhaseIndex, 1)
      expectNoDifference(
        snapshot.currentPhase,
        .breakTime(afterPeriod: 1, durationSeconds: 120)
      )
      expectNoDifference(snapshot.game.elapsedSeconds, 0)
      expectNoDifference(
        snapshot.game.timerEndsAt,
        Date(timeIntervalSince1970: 1_120)
      )
      expectNoDifference(snapshot.game.isAwaitingCentrePassConfirmation, true)
    }

    @Test
    func skippingBreakAdvancesToPausedQuarterWhileCentrePassRemainsPending() async throws {
      var game = Self.game()
      game.currentPhaseIndex = 1
      game.isAwaitingCentrePassConfirmation = true
      game.timerEndsAt = Date(timeIntervalSince1970: 1_100)
      let database = try await Self.seed(game)
      let client = GameTimerClient.live

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.skip(UUID(3), 1)
      }

      expectNoDifference(snapshot.game.currentPhaseIndex, 2)
      expectNoDifference(
        snapshot.currentPhase,
        .period(number: 2, durationSeconds: 900)
      )
      expectNoDifference(snapshot.game.countdown, GameCountdown())
      expectNoDifference(snapshot.game.isAwaitingCentrePassConfirmation, true)
    }

    @Test
    func zeroLengthBreakPassesStraightToPausedNextQuarter() async throws {
      let game = Self.game()
      let periods = testGamePeriods(
        gameID: game.id,
        durationSeconds: 900,
        breakDurations: [0, 300, 120]
      )
      let database = try await Self.seed(game, periods: periods)

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        @Dependency(\.gameTimer) var client
        return try await client.skip(UUID(3), 0)
      }

      expectNoDifference(snapshot.game.currentPhaseIndex, 2)
      expectNoDifference(snapshot.game.countdown, GameCountdown())
      expectNoDifference(snapshot.game.isAwaitingCentrePassConfirmation, true)
    }

    @Test
    func reconciliationCanCrossAQuarterAndItsBreak() async throws {
      var game = Self.game()
      game.timerEndsAt = Date(timeIntervalSince1970: 1_050)
      let database = try await Self.seed(game)
      let client = GameTimerClient.live

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_300)
        $0.defaultDatabase = database
      } operation: {
        try await client.reconcile(UUID(3))
      }

      expectNoDifference(snapshot.game.currentPhaseIndex, 2)
      expectNoDifference(snapshot.game.countdown, GameCountdown())
      expectNoDifference(snapshot.game.isAwaitingCentrePassConfirmation, true)
    }

    @Test
    func pausedQuarterCannotRecordGoal() async throws {
      let database = try await Self.seed(Self.game())
      let store = TestStore(initialState: Self.state()) {
        ScoringFeature()
      } withDependencies: {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
        $0.uuid = .incrementing
      }

      await store.send(.goalButtonTapped(UUID(1)))

      let goals = try await database.read { db in try Goal.fetchAll(db) }
      expectNoDifference(goals, [])
    }

    @Test
    func runningQuarterRecordsGoalWithAuthoritativeQuarterAndElapsedTime() async throws {
      var game = Self.game()
      game.timerEndsAt = Date(timeIntervalSince1970: 1_600)
      let database = try await Self.seed(game)
      var state = Self.state()
      state.timerEndsAt = game.timerEndsAt
      let store = TestStore(initialState: state) {
        ScoringFeature()
      } withDependencies: {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
        $0.uuid = .incrementing
      }

      await store.send(.goalButtonTapped(UUID(1)))
      await store.receive {
        guard case .goalResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.canUndo = true
        $0.centrePassTeamID = UUID(2)
        $0.goalFeedbackTrigger = 1
        $0.teamAScore = 1
      }

      let goal = try await database.read { db in try Goal.fetchOne(db) }
      expectNoDifference(goal?.gamePeriodID, testGamePeriodID(gameID: UUID(3), position: 0))
      expectNoDifference(goal?.elapsedSeconds, 300)
    }

    @Test
    func disabledGoalSoundsDoNotPlay() async {
      let soundPlayed = LockIsolated(false)
      var state = Self.state()
      state.$soundEffectsEnabled.withLock { $0 = false }
      var gameTimer = GameTimerClient.live
      gameTimer.refreshActivity = { _ in }
      let store = TestStore(initialState: state) {
        ScoringFeature()
      } withDependencies: {
        $0.gameTimer = gameTimer
        $0.soundEffects = SoundEffectsClient(
          playGoal: { soundPlayed.setValue(true) }
        )
      }

      await store.send(
        .goalResponse(
          .success(
            ScoringFeature.ScoreSnapshot(
              canUndo: true,
              centrePassTeamID: UUID(2),
              teamAScore: 1
            )
          )
        )
      ) {
        $0.canUndo = true
        $0.centrePassTeamID = UUID(2)
        $0.goalFeedbackTrigger = 1
        $0.teamAScore = 1
      }
      await store.finish()

      expectNoDifference(soundPlayed.value, false)
    }

    @Test
    func pendingCentrePassBlocksNextQuarterStart() async {
      var quarter = Self.state()
      quarter.currentPhaseIndex = 2
      quarter.isShowingLastCentrePassBanner = true
      let quarterStore = TestStore(initialState: quarter) {
        ScoringFeature()
      }

      await quarterStore.send(.startTimerButtonTapped)
      expectNoDifference(quarterStore.state.timerEndsAt, nil)
    }

    @Test
    func skippingFinalQuarterMakesGameFinishable() async throws {
      var game = Self.game()
      game.currentPhaseIndex = 6
      let database = try await Self.seed(game)
      let client = GameTimerClient.live

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.skip(UUID(3), 6)
      }
      let state = ScoringFeature.State(snapshot: snapshot)

      expectNoDifference(snapshot.game.currentPhaseIndex, 6)
      expectNoDifference(snapshot.game.elapsedSeconds, 900)
      expectNoDifference(snapshot.game.timerEndsAt, nil)
      expectNoDifference(state.canFinishGame, true)
    }

    private nonisolated static func game() -> Game {
      Game(
        id: UUID(3),
        startedAt: Date(timeIntervalSince1970: 500),
        endedAt: nil,
        teamAID: UUID(1),
        teamBID: UUID(2),
        centrePassTeamID: UUID(1)
      )
    }

    private nonisolated static func periods() -> [GamePeriod] {
      testGamePeriods(
        gameID: UUID(3),
        durationSeconds: 900,
        breakDurations: [120, 300, 120]
      )
    }

    private nonisolated static func state() -> ScoringFeature.State {
      ScoringFeature.State(
        centrePassTeamID: UUID(1),
        gameID: UUID(3),
        periods: periods(),
        startedAt: Date(timeIntervalSince1970: 500),
        teamA: ScoringFeature.Team(id: UUID(1), name: "Ravens"),
        teamB: ScoringFeature.Team(id: UUID(2), name: "Swifts")
      )
    }

    private static func seed(
      _ game: Game,
      periods: [GamePeriod] = periods()
    ) async throws -> any DatabaseWriter {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      try await database.write { db in
        try db.seed {
          Team(id: UUID(1), name: "Ravens")
          Team(id: UUID(2), name: "Swifts")
          game
        }
        try GamePeriod.insert { periods }.execute(db)
      }
      return database
    }
  }
}
