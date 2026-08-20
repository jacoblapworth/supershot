import ComposableArchitecture
import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct ScoringFeatureTests {
    @Test
    func gameTimelineIsFourQuartersWithBreaksBetweenThem() {
      let game = Self.game()

      expectNoDifference(
        game.phases,
        [
          .quarter(number: 1, durationSeconds: 900),
          .breakTime(afterQuarter: 1, durationSeconds: 120),
          .quarter(number: 2, durationSeconds: 900),
          .breakTime(afterQuarter: 2, durationSeconds: 300),
          .quarter(number: 3, durationSeconds: 900),
          .breakTime(afterQuarter: 3, durationSeconds: 120),
          .quarter(number: 4, durationSeconds: 900),
        ]
      )
    }

    @Test
    func skippingQuarterStartsItsBreakAndRequestsLastCentrePass() async throws {
      let database = try await Self.seed(Self.game())
      let client = GameTimerClient.live(system: .noop)

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.skip(UUID(3), 0)
      }

      expectNoDifference(snapshot.game.currentPhaseIndex, 1)
      expectNoDifference(
        snapshot.game.currentPhase,
        .breakTime(afterQuarter: 1, durationSeconds: 120)
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
      let client = GameTimerClient.live(system: .noop)

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.skip(UUID(3), 1)
      }

      expectNoDifference(snapshot.game.currentPhaseIndex, 2)
      expectNoDifference(
        snapshot.game.currentPhase,
        .quarter(number: 2, durationSeconds: 900)
      )
      expectNoDifference(snapshot.game.countdown, GameCountdown())
      expectNoDifference(snapshot.game.isAwaitingCentrePassConfirmation, true)
    }

    @Test
    func zeroLengthBreakPassesStraightToPausedNextQuarter() async throws {
      var game = Self.game()
      game.firstBreakDurationSeconds = 0
      let database = try await Self.seed(game)
      let client = GameTimerClient.live(system: .noop)

      let snapshot = try await withDependencies {
        $0.date.now = Date(timeIntervalSince1970: 1_000)
        $0.defaultDatabase = database
      } operation: {
        try await client.skip(UUID(3), 0)
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
      let client = GameTimerClient.live(system: .noop)

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
      expectNoDifference(goal?.quarterNumber, 1)
      expectNoDifference(goal?.elapsedSeconds, 300)
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
      let client = GameTimerClient.live(system: .noop)

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
        centrePassTeamID: UUID(1),
        periodDurationSeconds: 900,
        firstBreakDurationSeconds: 120,
        halfTimeDurationSeconds: 300,
        secondBreakDurationSeconds: 120
      )
    }

    private nonisolated static func state() -> ScoringFeature.State {
      ScoringFeature.State(
        centrePassTeamID: UUID(1),
        firstBreakDurationSeconds: 120,
        gameID: UUID(3),
        halfTimeDurationSeconds: 300,
        periodDurationSeconds: 900,
        secondBreakDurationSeconds: 120,
        startedAt: Date(timeIntervalSince1970: 500),
        teamA: ScoringFeature.Team(id: UUID(1), name: "Ravens"),
        teamB: ScoringFeature.Team(id: UUID(2), name: "Swifts")
      )
    }

    private static func seed(_ game: Game) async throws -> any DatabaseWriter {
      @Dependency(\.defaultDatabase) var database
      try clearDatabase(database)
      try await database.write { db in
        try db.seed {
          Team(id: UUID(1), name: "Ravens")
          Team(id: UUID(2), name: "Swifts")
          game
        }
      }
      return database
    }
  }
}
