import Clocks
import ComposableArchitecture
import ConcurrencyExtras
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import OrderedCollections
import SQLiteData
import Testing

@testable import Netscore

@MainActor
@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
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
  func backgroundingPausesAndPersistsGameProgress() async throws {
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

    await store.send(.sceneBecameInactive) {
      $0.isTimerRunning = false
    }
    await store.finish()

    let snapshot = try await store.dependencies.defaultDatabase.read { db in
      try GameSnapshot.fetch(db, gameID: UUID(3))
    }
    let resumedState = ScoringFeature.State(snapshot: snapshot)

    expectNoDifference(snapshot.game.currentPeriod, 1)
    expectNoDifference(snapshot.game.elapsedSeconds, 1)
    expectNoDifference(snapshot.game.hasTimerStartedCurrentPeriod, true)
    expectNoDifference(resumedState.elapsedSeconds, 1)
    expectNoDifference(resumedState.hasTimerStartedThisPeriod, true)
    expectNoDifference(resumedState.isTimerRunning, false)
  }

  @Test
  func leavingScoringPausesPersistsAndDismisses() async throws {
    let didDismiss = LockIsolated(false)
    var state = Self.scoringState()
    state.elapsedSeconds = 123
    state.hasTimerStartedThisPeriod = true
    state.isTimerRunning = true
    state.period = 2
    let store = Self.makeScoringStore(
      state: state,
      dismiss: DismissEffect { didDismiss.setValue(true) }
    )

    await store.send(.closeButtonTapped) {
      $0.isTimerRunning = false
    }
    await store.finish()

    let game = try await store.dependencies.defaultDatabase.read { db in
      try Game.find(UUID(3)).fetchOne(db)
    }
    expectNoDifference(didDismiss.value, true)
    expectNoDifference(game?.currentPeriod, 2)
    expectNoDifference(game?.elapsedSeconds, 123)
    expectNoDifference(game?.hasTimerStartedCurrentPeriod, true)
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
  func finishGameStoresEndDateAndDelegatesGameID() async throws {
    let endedAt = Date(timeIntervalSince1970: 2_000)
    var state = Self.scoringState()
    state.hasTimerStartedThisPeriod = true
    state.period = 4
    state.teamAScore = 2
    state.teamBScore = 1
    let store = Self.makeScoringStore(state: state, date: endedAt)

    var finishedGameID: Game.ID?
    await store.send(.finishGameButtonTapped)
    await store.receive {
      guard case let .finishGameResponse(.success(gameID)) = $0 else { return false }
      finishedGameID = gameID
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
    expectNoDifference(game?.currentPeriod, 4)
    expectNoDifference(game?.hasTimerStartedCurrentPeriod, true)
    expectNoDifference(finishedGameID, UUID(3))
  }

  @Test
  func gameListIsNewestFirstWithScoresAndStatuses() async throws {
    @Dependency(\.defaultDatabase) var database
    try Self.clearDatabase(database)

    let olderDate = Date(timeIntervalSince1970: 1_000)
    let newerDate = Date(timeIntervalSince1970: 2_000)
    try await database.write { db in
      try db.seed {
        Team(id: UUID(-1), name: "Ravens")
        Team(id: UUID(-2), name: "Swifts")
        Team(id: UUID(-3), name: "Foxes")
        Team(id: UUID(-4), name: "Owls")
        Game(
          id: UUID(-1),
          startedAt: newerDate,
          endedAt: nil,
          teamAID: UUID(-1),
          teamBID: UUID(-2),
          periodDurationSeconds: 900
        )
        Game(
          id: UUID(-2),
          startedAt: olderDate,
          endedAt: Date(timeIntervalSince1970: 1_500),
          teamAID: UUID(-3),
          teamBID: UUID(-4),
          periodDurationSeconds: 900
        )
        Goal(
          id: UUID(-1),
          gameID: UUID(-1),
          teamID: UUID(-1),
          period: 1,
          elapsedSeconds: 10,
          points: 2,
          createdAt: newerDate
        )
        Goal(
          id: UUID(-2),
          gameID: UUID(-2),
          teamID: UUID(-4),
          period: 1,
          elapsedSeconds: 20,
          points: 1,
          createdAt: olderDate
        )
      }
    }

    let value = try await database.read { db in
      try GamesRequest().fetch(db)
    }

    expectNoDifference(
      value.games,
      [
        GameListItem(
          endedAt: nil,
          id: UUID(-1),
          startedAt: newerDate,
          teamAName: "Ravens",
          teamAScore: 2,
          teamBName: "Swifts",
          teamBScore: 0
        ),
        GameListItem(
          endedAt: Date(timeIntervalSince1970: 1_500),
          id: UUID(-2),
          startedAt: olderDate,
          teamAName: "Foxes",
          teamAScore: 0,
          teamBName: "Owls",
          teamBScore: 1
        ),
      ]
    )
  }

  @Test
  func resumableProgressFieldsHaveSafeDefaults() async throws {
    @Dependency(\.defaultDatabase) var database
    try Self.clearDatabase(database)

    try await database.write { db in
      try db.seed {
        Team(id: UUID(-1), name: "Ravens")
        Team(id: UUID(-2), name: "Swifts")
        Game(
          id: UUID(-1),
          startedAt: Date(timeIntervalSince1970: 1_000),
          endedAt: nil,
          teamAID: UUID(-1),
          teamBID: UUID(-2),
          periodDurationSeconds: 900
        )
      }
    }

    let game = try await database.read { db in
      try Game.find(UUID(-1)).fetchOne(db)
    }
    expectNoDifference(game?.currentPeriod, 1)
    expectNoDifference(game?.elapsedSeconds, 0)
    expectNoDifference(game?.hasTimerStartedCurrentPeriod, false)
  }

  @Test
  func multipleUnfinishedGamesRehydrateIndependentlyAndPaused() async throws {
    @Dependency(\.defaultDatabase) var database
    try Self.clearDatabase(database)

    try await database.write { db in
      try db.seed {
        Team(id: UUID(-1), name: "Ravens")
        Team(id: UUID(-2), name: "Swifts")
        Team(id: UUID(-3), name: "Foxes")
        Team(id: UUID(-4), name: "Owls")
        Game(
          id: UUID(-1),
          startedAt: Date(timeIntervalSince1970: 1_000),
          endedAt: nil,
          teamAID: UUID(-1),
          teamBID: UUID(-2),
          periodDurationSeconds: 900,
          currentPeriod: 3,
          elapsedSeconds: 42,
          hasTimerStartedCurrentPeriod: true
        )
        Game(
          id: UUID(-2),
          startedAt: Date(timeIntervalSince1970: 2_000),
          endedAt: nil,
          teamAID: UUID(-3),
          teamBID: UUID(-4),
          periodDurationSeconds: 600,
          currentPeriod: 2,
          elapsedSeconds: 75,
          hasTimerStartedCurrentPeriod: true
        )
        Goal(
          id: UUID(-1),
          gameID: UUID(-1),
          teamID: UUID(-2),
          period: 2,
          elapsedSeconds: 30,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_100)
        )
        Goal(
          id: UUID(-2),
          gameID: UUID(-2),
          teamID: UUID(-3),
          period: 1,
          elapsedSeconds: 20,
          points: 2,
          createdAt: Date(timeIntervalSince1970: 2_100)
        )
      }
    }

    let snapshots = try await database.read { db in
      (
        try GameSnapshot.fetch(db, gameID: UUID(-1)),
        try GameSnapshot.fetch(db, gameID: UUID(-2))
      )
    }
    let first = ScoringFeature.State(snapshot: snapshots.0)
    let second = ScoringFeature.State(snapshot: snapshots.1)

    expectNoDifference(first.period, 3)
    expectNoDifference(first.elapsedSeconds, 42)
    expectNoDifference(first.teamAScore, 0)
    expectNoDifference(first.teamBScore, 1)
    expectNoDifference(first.canUndo, true)
    expectNoDifference(first.isTimerRunning, false)
    expectNoDifference(second.period, 2)
    expectNoDifference(second.elapsedSeconds, 75)
    expectNoDifference(second.teamAScore, 2)
    expectNoDifference(second.teamBScore, 0)
    expectNoDifference(second.canUndo, true)
    expectNoDifference(second.isTimerRunning, false)
  }

  @Test
  func completedGameDetailBuildsChronologicalRunningScore() async throws {
    @Dependency(\.defaultDatabase) var database
    try Self.clearDatabase(database)

    let startedAt = Date(timeIntervalSince1970: 1_000)
    let endedAt = Date(timeIntervalSince1970: 2_000)
    try await database.write { db in
      try db.seed {
        Team(id: UUID(-1), name: "Ravens")
        Team(id: UUID(-2), name: "Swifts")
        Game(
          id: UUID(-1),
          startedAt: startedAt,
          endedAt: endedAt,
          teamAID: UUID(-1),
          teamBID: UUID(-2),
          periodDurationSeconds: 900
        )
        Goal(
          id: UUID(-3),
          gameID: UUID(-1),
          teamID: UUID(-2),
          period: 2,
          elapsedSeconds: 30,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_300)
        )
        Goal(
          id: UUID(-1),
          gameID: UUID(-1),
          teamID: UUID(-1),
          period: 1,
          elapsedSeconds: 100,
          points: 2,
          createdAt: Date(timeIntervalSince1970: 1_100)
        )
        Goal(
          id: UUID(-2),
          gameID: UUID(-1),
          teamID: UUID(-2),
          period: 1,
          elapsedSeconds: 200,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_200)
        )
      }
    }

    let value = try await database.read { db in
      try GameDetailRequest(gameID: UUID(-1)).fetch(db)
    }

    expectNoDifference(
      value.detail,
      CompletedGameDetail(
        endedAt: endedAt,
        goals: [
          GoalTimelineItem(
            clockSecondsRemaining: 800,
            id: UUID(-1),
            period: 1,
            points: 2,
            scoringTeamName: "Ravens",
            teamAScore: 2,
            teamBScore: 0
          ),
          GoalTimelineItem(
            clockSecondsRemaining: 700,
            id: UUID(-2),
            period: 1,
            points: 1,
            scoringTeamName: "Swifts",
            teamAScore: 2,
            teamBScore: 1
          ),
          GoalTimelineItem(
            clockSecondsRemaining: 870,
            id: UUID(-3),
            period: 2,
            points: 1,
            scoringTeamName: "Swifts",
            teamAScore: 2,
            teamBScore: 2
          ),
        ],
        id: UUID(-1),
        startedAt: startedAt,
        teamAName: "Ravens",
        teamAScore: 2,
        teamBName: "Swifts",
        teamBScore: 2
      )
    )
  }

  @Test
  func finishingGameReplacesScoringWithDetailRoute() async {
    var state = AppFeature.State()
    state.path.append(.scoring(Self.scoringState()))
    let scoringID = state.path.ids[0]
    let store = TestStore(initialState: state) {
      AppFeature()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .path(
        .element(
          id: scoringID,
          action: .scoring(.delegate(.gameFinished(UUID(3))))
        )
      )
    )

    expectNoDifference(store.state.path.count, 1)
    guard case let .gameDetail(detail) = store.state.path[0] else {
      Issue.record("Expected the completed game detail route")
      return
    }
    expectNoDifference(detail.gameID, UUID(3))
  }

  private static func makeScoringStore(
    state: ScoringFeature.State = scoringState(),
    date: Date = Date(timeIntervalSince1970: 1_000),
    clock: TestClock<Duration>? = nil,
    dismiss: DismissEffect? = nil
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
            periodDurationSeconds: state.periodDurationSeconds,
            currentPeriod: state.period,
            elapsedSeconds: state.elapsedSeconds,
            hasTimerStartedCurrentPeriod: state.hasTimerStartedThisPeriod
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
