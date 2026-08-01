import Clocks
import ComposableArchitecture
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@testable import Netscore

@MainActor
@Suite(.serialized)
struct NetscoreTests {
  @Test
  func setupValidationRequiresDifferentTeamNames() async {
    var state = SetupFeature.State()
    state.teamAName = "Ravens"
    state.teamBName = "Ravens"

    let store = TestStore(initialState: state) {
      SetupFeature()
    }

    await store.send(.startGameButtonTapped) {
      $0.errorMessage = "Enter two different team names."
    }
  }

  @Test
  func startGameCreatesTeamsAndGame() async throws {
    var state = SetupFeature.State()
    state.teamAName = "Ravens"
    state.teamBName = "Swifts"

    let startedAt = Date(timeIntervalSince1970: 1_000)
    let store = TestStore(initialState: state) {
      SetupFeature()
    } withDependencies: {
      $0.date.now = startedAt
      $0.uuid = .incrementing
      try! $0.bootstrapDatabase()
      try! Self.clearDatabase($0.defaultDatabase)
    }

    var scoringState: ScoringFeature.State?
    await store.send(.startGameButtonTapped) {
      $0.isSaving = true
    }
    await store.receive {
      guard case let .startGameResponse(.success(state)) = $0 else { return false }
      scoringState = state
      return true
    } assert: {
      $0.isSaving = false
    }
    await store.receive {
      guard case .delegate(.gameStarted) = $0 else { return false }
      return true
    }

    let database = store.dependencies.defaultDatabase
    let teams = try await database.read { db in
      try Team.order(by: \.name).fetchAll(db)
    }
    let games = try await database.read { db in
      try Game.fetchAll(db)
    }

    expectNoDifference(teams.map { $0.name }, ["Ravens", "Swifts"])
    expectNoDifference(games.count, 1)
    expectNoDifference(games.first?.startedAt, startedAt)
    expectNoDifference(scoringState?.teamA.name, "Ravens")
    expectNoDifference(scoringState?.teamB.name, "Swifts")
  }

  @Test
  func timerStartsPausesAndResumes() async throws {
    let clock = TestClock()
    let store = Self.makeScoringStore(clock: clock)

    await store.send(.startTimerButtonTapped) {
      $0.hasTimerStartedThisPeriod = true
      $0.isTimerRunning = true
    }

    await clock.advance(by: .seconds(1))
    await store.receive {
      guard case .timerTick = $0 else { return false }
      return true
    } assert: {
      $0.elapsedSeconds = 1
    }

    await store.send(.pauseTimerButtonTapped) {
      $0.isTimerRunning = false
    }

    await store.send(.resumeTimerButtonTapped) {
      $0.isTimerRunning = true
    }

    await clock.advance(by: .seconds(1))
    await store.receive {
      guard case .timerTick = $0 else { return false }
      return true
    } assert: {
      $0.elapsedSeconds = 2
    }

    await store.send(.pauseTimerButtonTapped) {
      $0.isTimerRunning = false
    }
  }

  @Test
  func timerAutoPausesAtPeriodEnd() async throws {
    let clock = TestClock()
    var state = Self.scoringState()
    state.elapsedSeconds = state.periodDurationSeconds - 1
    let store = Self.makeScoringStore(state: state, clock: clock)

    await store.send(.resumeTimerButtonTapped) {
      $0.hasTimerStartedThisPeriod = true
      $0.isTimerRunning = true
    }

    await clock.advance(by: .seconds(1))
    await store.receive {
      guard case .timerTick = $0 else { return false }
      return true
    } assert: {
      $0.elapsedSeconds = $0.periodDurationSeconds
      $0.isTimerRunning = false
    }
  }

  @Test
  func nextQuarterResetsTimer() async throws {
    var state = Self.scoringState()
    state.elapsedSeconds = 42
    state.hasTimerStartedThisPeriod = true
    let store = Self.makeScoringStore(state: state)

    await store.send(.nextQuarterButtonTapped) {
      $0.elapsedSeconds = 0
      $0.hasTimerStartedThisPeriod = false
      $0.period = 2
    }
  }

  @Test
  func nextQuarterUnavailableBeforePeriodStarts() async throws {
    let store = Self.makeScoringStore()

    await store.send(.nextQuarterButtonTapped)
  }

  @Test
  func pausedScoringRequiresConfirmationAndPersistsGoal() async throws {
    let store = Self.makeScoringStore()

    await store.send(.goalButtonTapped(UUID(1))) {
      $0.confirmationDialog = ConfirmationDialogState<ScoringFeature.ConfirmationDialogAction>.pausedGoalConfirmation
      $0.pendingPausedGoalTeamID = UUID(1)
    }

    await store.send(.confirmationDialog(.presented(.recordGoalButtonTapped))) {
      $0.confirmationDialog = nil
      $0.pendingPausedGoalTeamID = nil
    }

    await store.receive {
      guard case .goalResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.canUndo = true
      $0.teamAScore = 1
    }

    let goals = try await store.dependencies.defaultDatabase.read { db in
      try Goal.fetchAll(db)
    }
    expectNoDifference(goals.count, 1)
    expectNoDifference(goals.first?.teamID, UUID(1))
    expectNoDifference(goals.first?.period, 1)
    expectNoDifference(goals.first?.elapsedSeconds, 0)
  }

  @Test
  func undoRemovesLatestGoal() async throws {
    var state = Self.scoringState()
    state.isTimerRunning = true
    let store = Self.makeScoringStore(state: state)

    await store.send(.goalButtonTapped(UUID(1)))
    await store.receive {
      guard case .goalResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.canUndo = true
      $0.teamAScore = 1
    }

    await store.send(.goalButtonTapped(UUID(2)))
    await store.receive {
      guard case .goalResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.teamBScore = 1
    }

    await store.send(.undoButtonTapped)
    await store.receive {
      guard case .undoResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.teamBScore = 0
    }

    let goals = try await store.dependencies.defaultDatabase.read { db in
      try Goal.fetchAll(db)
    }
    expectNoDifference(goals.count, 1)
    expectNoDifference(goals.first?.teamID, UUID(1))
  }

  @Test
  func finishGameStoresEndDateAndDelegatesSummary() async throws {
    let endedAt = Date(timeIntervalSince1970: 2_000)
    var state = Self.scoringState()
    state.hasTimerStartedThisPeriod = true
    state.period = 4
    state.teamAScore = 2
    state.teamBScore = 1
    let store = Self.makeScoringStore(state: state, date: endedAt)

    var summary: SummaryFeature.State?
    await store.send(.finishGameButtonTapped)
    await store.receive {
      guard case let .finishGameResponse(.success(state)) = $0 else { return false }
      summary = state
      return true
    }
    await store.receive {
      guard case .delegate(.gameFinished) = $0 else { return false }
      return true
    }

    let game = try await store.dependencies.defaultDatabase.read { db in
      try Game.find(UUID(3)).fetchOne(db)
    }
    expectNoDifference(game?.endedAt, endedAt)
    expectNoDifference(summary?.resultTitle, "Ravens win")
  }

  private static func makeScoringStore(
    state: ScoringFeature.State = scoringState(),
    date: Date = Date(timeIntervalSince1970: 1_000),
    clock: TestClock<Duration>? = nil
  ) -> TestStoreOf<ScoringFeature> {
    TestStore(initialState: state) {
      ScoringFeature()
    } withDependencies: {
      $0.date.now = date
      $0.uuid = .incrementing
      try! $0.bootstrapDatabase()
      try! Self.clearDatabase($0.defaultDatabase)
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
            periodDurationSeconds: state.periodDurationSeconds
          )
        }
        .execute(db)
      }
      if let clock {
        $0.continuousClock = clock
      }
    }
  }

  private nonisolated static func clearDatabase(_ database: any DatabaseWriter) throws {
    try database.write { db in
      try Goal.delete().execute(db)
      try Game.delete().execute(db)
      try Team.delete().execute(db)
    }
  }

  private nonisolated static func scoringState() -> ScoringFeature.State {
    ScoringFeature.State(
      gameID: UUID(3),
      startedAt: Date(timeIntervalSince1970: 500),
      teamA: ScoringFeature.Team(id: UUID(1), name: "Ravens"),
      teamB: ScoringFeature.Team(id: UUID(2), name: "Swifts")
    )
  }
}
