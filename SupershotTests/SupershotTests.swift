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

@testable import Supershot

@MainActor
@Suite(
  .serialized,
  .dependencies {
    try $0.bootstrapDatabase()
  }
)
struct SupershotTests {
  @Test
  func setupValidationRequiresDifferentTeamNames() async {
    let state = Self.setupState(leftName: "Ravens", rightName: "Ravens")

    let store = TestStore(initialState: state) {
      SetupFeature()
    }

    await store.send(.startGameButtonTapped) {
      $0.errorMessage = "Team names must be unique."
    }
  }

  @Test
  func setupValidationRequiresFirstCentrePass() async {
    let state = Self.setupState(leftName: "Ravens", rightName: "Swifts")

    let store = TestStore(initialState: state) {
      SetupFeature()
    }

    await store.send(.startGameButtonTapped) {
      $0.errorMessage = "Choose the team taking the first centre pass."
    }
  }

  @Test
  func startGameCreatesTeamsAndGame() async throws {
    var state = Self.setupState(leftName: "Ravens", rightName: "Swifts")
    state.firstCentrePass = .teamB

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
    expectNoDifference(teams.map { $0.normalizedName }, ["ravens", "swifts"])
    expectNoDifference(teams.map { $0.colorHex }, [TeamColorPalette.blue, TeamColorPalette.red])
    expectNoDifference(games.count, 1)
    expectNoDifference(games.first?.startedAt, startedAt)
    expectNoDifference(games.first?.centrePassTeamID, scoringState?.teamB.id)
    expectNoDifference(games.first?.firstBreakDurationSeconds, 240)
    expectNoDifference(games.first?.halfTimeDurationSeconds, 240)
    expectNoDifference(games.first?.secondBreakDurationSeconds, 240)
    expectNoDifference(scoringState?.centrePassTeamID, scoringState?.teamB.id)
    expectNoDifference(scoringState?.teamA.name, "Ravens")
    expectNoDifference(scoringState?.teamB.name, "Swifts")
    expectNoDifference(scoringState?.teamA.colorHex, TeamColorPalette.blue)
    expectNoDifference(scoringState?.teamB.colorHex, TeamColorPalette.red)
  }

  @Test
  func editingSavedTeamsIsStagedAndSupportsSafeNameSwaps() async throws {
    let ravens = Team(id: UUID(30), name: "Ravens", colorHex: TeamColorPalette.blue)
    let swifts = Team(id: UUID(31), name: "Swifts", colorHex: TeamColorPalette.red)
    var state = SetupFeature.State()
    state.availableTeams = [ravens, swifts]
    state.firstCentrePass = .teamA
    state.leftTeam.mode = .locked
    state.leftTeam.selection = .existing(
      original: ravens,
      draft: TeamSlotFeature.TeamDraft(colorHex: "#34C759", name: "Swifts")
    )
    state.rightTeam.mode = .locked
    state.rightTeam.selection = .existing(
      original: swifts,
      draft: TeamSlotFeature.TeamDraft(colorHex: "#FF9500", name: "Ravens")
    )

    let store = TestStore(initialState: state) {
      SetupFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_000)
      $0.uuid = .incrementing
      try! $0.bootstrapDatabase()
      try! Self.clearDatabase($0.defaultDatabase)
      try! $0.defaultDatabase.write { db in
        try Team.insert {
          ravens
          swifts
        }
        .execute(db)
      }
    }

    await store.send(.startGameButtonTapped) {
      $0.confirmationDialog = .confirmTeamUpdates(
        message: "Ravens will become Swifts in game history. "
          + "Swifts will become Ravens in game history."
      )
    }
    await store.send(
      .confirmationDialog(.presented(.updateAndStartButtonTapped))
    ) {
      $0.confirmationDialog = nil
      $0.isSaving = true
    }
    await store.receive {
      guard case .startGameResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.isSaving = false
    }
    await store.receive {
      guard case .delegate(.gameStarted) = $0 else { return false }
      return true
    }

    let values = try await store.dependencies.defaultDatabase.read { db in
      (
        try Team.find(ravens.id).fetchOne(db),
        try Team.find(swifts.id).fetchOne(db),
        try Game.fetchOne(db)
      )
    }
    expectNoDifference(values.0?.name, "Swifts")
    expectNoDifference(values.0?.normalizedName, "swifts")
    expectNoDifference(values.0?.colorHex, "#34C759")
    expectNoDifference(values.1?.name, "Ravens")
    expectNoDifference(values.1?.normalizedName, "ravens")
    expectNoDifference(values.1?.colorHex, "#FF9500")
    expectNoDifference(values.2?.teamAID, ravens.id)
    expectNoDifference(values.2?.teamBID, swifts.id)
  }

  @Test
  func cancellingAndRevertingTeamEditsKeepsTheSavedDraft() async {
    let ravens = Team(id: UUID(20), name: "Ravens", colorHex: TeamColorPalette.blue)
    var state = TeamSlotFeature.State(side: .left)
    state.mode = .locked
    state.selection = .existing(
      original: ravens,
      draft: TeamSlotFeature.TeamDraft(colorHex: ravens.colorHex, name: ravens.name)
    )
    let store = TestStore(initialState: state) {
      TeamSlotFeature()
    }

    await store.send(.editTeamButtonTapped) {
      $0.editor = TeamSlotFeature.TeamDraft(colorHex: ravens.colorHex, name: ravens.name)
      $0.mode = .editing
    }
    await store.send(.binding(.set(\.editor.name, "Falcons"))) {
      $0.editor.name = "Falcons"
    }
    await store.send(.cancelButtonTapped) {
      $0.mode = .locked
    }
    expectNoDifference(store.state.selectedDraft?.name, "Ravens")

    await store.send(.editTeamButtonTapped) {
      $0.editor.name = "Ravens"
      $0.mode = .editing
    }
    await store.send(.binding(.set(\.editor.name, "Falcons"))) {
      $0.editor.name = "Falcons"
    }
    await store.send(.paletteColorButtonTapped("#34C759")) {
      $0.editor.colorHex = "#34C759"
    }
    await store.send(.doneButtonTapped) {
      $0.mode = .locked
      $0.selection = .existing(
        original: ravens,
        draft: TeamSlotFeature.TeamDraft(colorHex: "#34C759", name: "Falcons")
      )
    }
    await store.send(.revertChangesButtonTapped) {
      $0.selection = .existing(
        original: ravens,
        draft: TeamSlotFeature.TeamDraft(colorHex: ravens.colorHex, name: ravens.name)
      )
    }
  }

  @Test
  func emptyTeamCardOffersExistingTeamsAndCreateFlow() async {
    let ravens = Team(id: UUID(20), name: "Ravens", colorHex: "#AF52DE")
    var state = SetupFeature.State()
    state.availableTeams = [ravens]
    let store = TestStore(initialState: state) {
      SetupFeature()
    }

    await store.send(.leftTeam(.cardTapped)) {
      $0.leftTeam.mode = .choosing
    }
    await store.send(.leftTeam(.existingTeamSelected(ravens))) {
      $0.leftTeam.mode = .locked
      $0.leftTeam.selection = .existing(
        original: ravens,
        draft: TeamSlotFeature.TeamDraft(
          colorHex: "#AF52DE",
          name: "Ravens"
        )
      )
    }

    await store.send(.rightTeam(.cardTapped)) {
      $0.rightTeam.mode = .choosing
    }
    await store.send(.rightTeam(.createTeamButtonTapped)) {
      $0.rightTeam.mode = .creating
    }
  }

  @Test
  func swappingTeamsSwapsCompleteSelectionsAndFirstCentrePass() async {
    var state = Self.setupState(leftName: "Ravens", rightName: "Swifts")
    state.firstCentrePass = .teamA
    let store = TestStore(initialState: state) {
      SetupFeature()
    }

    await store.send(.swapTeamsButtonTapped) {
      let leftSelection = $0.leftTeam.selection
      $0.leftTeam.selection = $0.rightTeam.selection
      $0.rightTeam.selection = leftSelection
      $0.firstCentrePass = .teamB
    }

    expectNoDifference(store.state.leftTeam.selectedDraft?.name, "Swifts")
    expectNoDifference(store.state.leftTeam.selectedDraft?.colorHex, TeamColorPalette.red)
    expectNoDifference(store.state.rightTeam.selectedDraft?.name, "Ravens")
    expectNoDifference(store.state.rightTeam.selectedDraft?.colorHex, TeamColorPalette.blue)
  }

  @Test
  func breakDurationsCanBeUniformOrCustomized() async {
    let store = TestStore(initialState: SetupFeature.State()) {
      SetupFeature()
    }

    await store.send(.allBreakPresetButtonTapped(120)) {
      $0.firstBreakDuration = .init(totalSeconds: 120)
      $0.halfTimeDuration = .init(totalSeconds: 120)
      $0.secondBreakDuration = .init(totalSeconds: 120)
    }
    await store.send(.customizeBreaksButtonTapped) {
      $0.customizesBreaks = true
    }
    await store.send(.halfTimePresetButtonTapped(600)) {
      $0.halfTimeDuration = .init(totalSeconds: 600)
    }
    await store.send(.useFirstBreakForAllButtonTapped) {
      $0.customizesBreaks = false
      $0.halfTimeDuration = .init(totalSeconds: 120)
      $0.secondBreakDuration = .init(totalSeconds: 120)
    }

    var invalidState = Self.setupState(leftName: "Ravens", rightName: "Swifts")
    invalidState.firstCentrePass = .teamA
    invalidState.periodDuration = .init(totalSeconds: 0)
    expectNoDifference(invalidState.canStartGame, false)
    invalidState.periodDuration = .init(totalSeconds: 1)
    invalidState.halfTimeDuration.minutesText = "100"
    expectNoDifference(invalidState.canStartGame, false)
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
      $0.isShowingLastCentrePassBanner = true
      $0.isTimerRunning = false
    }
  }

  @Test
  func nextQuarterResetsTimer() async throws {
    var state = Self.scoringState()
    state.elapsedSeconds = 42
    state.hasTimerStartedThisPeriod = true
    let store = Self.makeScoringStore(state: state)

    await store.send(.endQuarterButtonTapped) {
      $0.isShowingLastCentrePassBanner = true
    }
    await store.send(.lastCentrePassNotTakenButtonTapped) {
      $0.isTransitioningPeriod = true
    }
    await store.receive {
      guard case .lastCentrePassResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.elapsedSeconds = 0
      $0.hasTimerStartedThisPeriod = false
      $0.isShowingLastCentrePassBanner = false
      $0.isTransitioningPeriod = false
      $0.period = 2
    }

    let game = try await store.dependencies.defaultDatabase.read { db in
      try Game.find(UUID(3)).fetchOne(db)
    }
    expectNoDifference(game?.centrePassTeamID, UUID(1))
    expectNoDifference(game?.currentPeriod, 2)
    expectNoDifference(game?.elapsedSeconds, 0)
    expectNoDifference(game?.isAwaitingCentrePassConfirmation, false)
  }

  @Test
  func takenLastCentrePassSwitchesTeamForNextQuarter() async throws {
    var state = Self.scoringState()
    state.elapsedSeconds = 42
    state.hasTimerStartedThisPeriod = true
    let store = Self.makeScoringStore(state: state)

    await store.send(.endQuarterButtonTapped) {
      $0.isShowingLastCentrePassBanner = true
    }
    await store.send(.lastCentrePassTakenButtonTapped) {
      $0.isTransitioningPeriod = true
    }
    await store.receive {
      guard case .lastCentrePassResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.centrePassTeamID = UUID(2)
      $0.elapsedSeconds = 0
      $0.hasTimerStartedThisPeriod = false
      $0.isShowingLastCentrePassBanner = false
      $0.isTransitioningPeriod = false
      $0.period = 2
    }

    let game = try await store.dependencies.defaultDatabase.read { db in
      try Game.find(UUID(3)).fetchOne(db)
    }
    expectNoDifference(game?.centrePassTeamID, UUID(2))
    expectNoDifference(game?.currentPeriod, 2)
  }

  @Test
  func lastCentrePassBannerKeepsQuarterUntilAnswered() async throws {
    var state = Self.scoringState()
    state.elapsedSeconds = 42
    state.hasTimerStartedThisPeriod = true
    let store = Self.makeScoringStore(state: state)

    await store.send(.endQuarterButtonTapped) {
      $0.isShowingLastCentrePassBanner = true
    }

    expectNoDifference(store.state.period, 1)
    expectNoDifference(store.state.elapsedSeconds, 42)
    expectNoDifference(store.state.centrePassTeamID, UUID(1))
    expectNoDifference(store.state.canMoveToNextQuarter, false)
  }

  @Test
  func nextQuarterUnavailableBeforePeriodStarts() async throws {
    let store = Self.makeScoringStore()

    await store.send(.endQuarterButtonTapped)
  }

  @Test
  func endingQuarterRunsConfiguredBreakThenWaitsForContinue() async throws {
    let clock = TestClock()
    var state = Self.scoringState()
    state.elapsedSeconds = 42
    state.firstBreakDurationSeconds = 2
    state.hasTimerStartedThisPeriod = true
    let store = Self.makeScoringStore(state: state, clock: clock)

    await store.send(.endQuarterButtonTapped) {
      $0.clockPhase = .breakTime
      $0.elapsedSeconds = 0
      $0.isShowingLastCentrePassBanner = true
      $0.isTimerRunning = true
    }
    await store.send(.lastCentrePassNotTakenButtonTapped) {
      $0.isTransitioningPeriod = true
    }
    await store.receive {
      guard case .lastCentrePassResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.isShowingLastCentrePassBanner = false
      $0.isTransitioningPeriod = false
    }

    await clock.advance(by: .seconds(1))
    await store.receive {
      guard case .timerTick = $0 else { return false }
      return true
    } assert: {
      $0.elapsedSeconds = 1
    }

    await clock.advance(by: .seconds(1))
    await store.receive {
      guard case .timerTick = $0 else { return false }
      return true
    } assert: {
      $0.elapsedSeconds = 2
      $0.isTimerRunning = false
    }

    expectNoDifference(store.state.canContinueToNextQuarter, true)
    await store.send(.continueToNextQuarterButtonTapped) {
      $0.isTransitioningPeriod = true
    }
    await store.receive {
      guard case .nextQuarterResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.clockPhase = .quarter
      $0.elapsedSeconds = 0
      $0.hasTimerStartedThisPeriod = false
      $0.isTransitioningPeriod = false
      $0.period = 2
    }

    expectNoDifference(store.state.isShowingOriginalTeamOrder, false)
    let game = try await store.dependencies.defaultDatabase.read { db in
      try Game.find(UUID(3)).fetchOne(db)
    }
    expectNoDifference(game?.currentPeriod, 2)
    expectNoDifference(game?.isInBreak, false)
  }

  @Test
  func halfTimeUsesItsOwnDurationAndDisablesGoals() async throws {
    var state = Self.scoringState()
    state.clockPhase = .breakTime
    state.elapsedSeconds = 60
    state.firstBreakDurationSeconds = 120
    state.halfTimeDurationSeconds = 600
    state.hasTimerStartedThisPeriod = true
    state.period = 2
    state.secondBreakDurationSeconds = 300
    let store = Self.makeScoringStore(state: state)

    expectNoDifference(store.state.currentDurationSeconds, 600)
    expectNoDifference(store.state.isShowingOriginalTeamOrder, false)
    await store.send(.goalButtonTapped(UUID(1)))
    await store.send(.centrePassTeamButtonTapped(UUID(2)))

    await store.send(.skipBreakButtonTapped) {
      $0.elapsedSeconds = 600
      $0.isTransitioningPeriod = true
    }
    await store.receive {
      guard case .nextQuarterResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.clockPhase = .quarter
      $0.elapsedSeconds = 0
      $0.hasTimerStartedThisPeriod = false
      $0.isTransitioningPeriod = false
      $0.period = 3
    }

    expectNoDifference(store.state.isShowingOriginalTeamOrder, true)
  }

  @Test
  func zeroDurationBreakAdvancesToNextQuarterPaused() async throws {
    var state = Self.scoringState()
    state.elapsedSeconds = 42
    state.hasTimerStartedThisPeriod = true
    let store = Self.makeScoringStore(state: state)

    await store.send(.endQuarterButtonTapped) {
      $0.isShowingLastCentrePassBanner = true
      $0.isTimerRunning = false
    }
    await store.send(.lastCentrePassNotTakenButtonTapped) {
      $0.isTransitioningPeriod = true
    }
    await store.receive {
      guard case .lastCentrePassResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.elapsedSeconds = 0
      $0.hasTimerStartedThisPeriod = false
      $0.isShowingLastCentrePassBanner = false
      $0.isTransitioningPeriod = false
      $0.period = 2
    }
  }

  @Test
  func fourthQuarterNeverEntersABreak() async throws {
    let clock = TestClock()
    var state = Self.scoringState()
    state.elapsedSeconds = state.periodDurationSeconds - 1
    state.firstBreakDurationSeconds = 120
    state.halfTimeDurationSeconds = 600
    state.period = 4
    state.secondBreakDurationSeconds = 300
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

    expectNoDifference(store.state.clockPhase, .quarter)
    expectNoDifference(store.state.canFinishGame, true)
  }

  @Test
  func evenQuarterGoalRemainsAttributedToDisplayedTeamIdentity() async throws {
    var state = Self.scoringState()
    state.isTimerRunning = true
    state.period = 2
    let store = Self.makeScoringStore(state: state)

    expectNoDifference(store.state.isShowingOriginalTeamOrder, false)
    await store.send(.goalButtonTapped(UUID(2)))
    await store.receive {
      guard case .goalResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.canUndo = true
      $0.centrePassTeamID = UUID(2)
      $0.teamBScore = 1
    }

    let goal = try await store.dependencies.defaultDatabase.read { db in
      try Goal.fetchOne(db)
    }
    expectNoDifference(goal?.teamID, UUID(2))
    expectNoDifference(goal?.period, 2)
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
    expectNoDifference(snapshot.game.centrePassTeamID, UUID(1))
    expectNoDifference(resumedState.centrePassTeamID, UUID(1))
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
    expectNoDifference(game?.centrePassTeamID, UUID(1))
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
      $0.centrePassTeamID = UUID(2)
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
      $0.centrePassTeamID = UUID(2)
      $0.teamAScore = 1
    }

    await store.send(.goalButtonTapped(UUID(2)))
    await store.receive {
      guard case .goalResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.centrePassTeamID = UUID(1)
      $0.teamBScore = 1
    }

    await store.send(.undoButtonTapped)
    await store.receive {
      guard case .undoResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.centrePassTeamID = UUID(2)
      $0.teamBScore = 0
    }

    let goals = try await store.dependencies.defaultDatabase.read { db in
      try Goal.fetchAll(db)
    }
    expectNoDifference(goals.count, 1)
    expectNoDifference(goals.first?.teamID, UUID(1))
  }

  @Test
  func centrePassCorrectionPersistsAndControlsNextGoal() async throws {
    var state = Self.scoringState()
    state.isTimerRunning = true
    let store = Self.makeScoringStore(state: state)

    await store.send(.centrePassTeamButtonTapped(UUID(2)))
    await store.receive {
      guard case let .centrePassTeamResponse(.success(teamID)) = $0 else { return false }
      return teamID == UUID(2)
    } assert: {
      $0.centrePassTeamID = UUID(2)
    }

    let snapshot = try await store.dependencies.defaultDatabase.read { db in
      try GameSnapshot.fetch(db, gameID: UUID(3))
    }
    expectNoDifference(ScoringFeature.State(snapshot: snapshot).centrePassTeamID, UUID(2))

    await store.send(.goalButtonTapped(UUID(1)))
    await store.receive {
      guard case .goalResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.canUndo = true
      $0.centrePassTeamID = UUID(1)
      $0.teamAScore = 1
    }
  }

  @Test
  func failedGoalWriteLeavesScoreAndCentrePassUnchanged() async throws {
    var state = Self.scoringState()
    state.isTimerRunning = true
    let store = Self.makeScoringStore(state: state)
    try await store.dependencies.defaultDatabase.write { db in
      try Game.find(UUID(3)).delete().execute(db)
    }

    await store.send(.goalButtonTapped(UUID(1)))
    await store.receive {
      guard case .goalResponse(.failure) = $0 else { return false }
      return true
    }

    expectNoDifference(store.state.centrePassTeamID, UUID(1))
    expectNoDifference(store.state.teamAScore, 0)
    expectNoDifference(store.state.canUndo, false)
  }

  @Test
  func failedCentrePassCorrectionLeavesSelectionUnchanged() async throws {
    let store = Self.makeScoringStore()
    try await store.dependencies.defaultDatabase.write { db in
      try Game.find(UUID(3)).delete().execute(db)
    }

    await store.send(.centrePassTeamButtonTapped(UUID(2)))
    await store.receive {
      guard case .centrePassTeamResponse(.failure) = $0 else { return false }
      return true
    }

    expectNoDifference(store.state.centrePassTeamID, UUID(1))
  }

  @Test
  func invalidCentrePassTeamIsIgnored() async throws {
    let store = Self.makeScoringStore()

    await store.send(.centrePassTeamButtonTapped(UUID(99)))

    expectNoDifference(store.state.centrePassTeamID, UUID(1))
  }

  @Test
  func failedQuarterTransitionLeavesProgressUnchanged() async throws {
    var state = Self.scoringState()
    state.elapsedSeconds = 42
    state.hasTimerStartedThisPeriod = true
    let store = Self.makeScoringStore(state: state)
    try await store.dependencies.defaultDatabase.write { db in
      try Game.find(UUID(3)).delete().execute(db)
    }

    await store.send(.endQuarterButtonTapped) {
      $0.isShowingLastCentrePassBanner = true
    }
    await store.send(.lastCentrePassTakenButtonTapped) {
      $0.isTransitioningPeriod = true
    }
    await store.receive {
      guard case .lastCentrePassResponse(.failure) = $0 else { return false }
      return true
    } assert: {
      $0.isTransitioningPeriod = false
    }

    expectNoDifference(store.state.centrePassTeamID, UUID(1))
    expectNoDifference(store.state.elapsedSeconds, 42)
    expectNoDifference(store.state.hasTimerStartedThisPeriod, true)
    expectNoDifference(store.state.isShowingLastCentrePassBanner, true)
    expectNoDifference(store.state.period, 1)
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
    expectNoDifference(game?.centrePassTeamID, UUID(1))
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
        Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
        Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
        Team(id: UUID(-3), name: "Foxes", colorHex: "#34C759")
        Team(id: UUID(-4), name: "Owls", colorHex: "#FF9500")
        Game(
          id: UUID(-1),
          startedAt: newerDate,
          endedAt: nil,
          teamAID: UUID(-1),
          teamBID: UUID(-2),
          periodDurationSeconds: 900,
          firstBreakDurationSeconds: 240,
          halfTimeDurationSeconds: 600,
          secondBreakDurationSeconds: 240
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
          firstBreakDurationSeconds: 240,
          halfTimeDurationSeconds: 600,
          id: UUID(-1),
          periodDurationSeconds: 900,
          secondBreakDurationSeconds: 240,
          startedAt: newerDate,
          teamAColorHex: TeamColorPalette.blue,
          teamAName: "Ravens",
          teamAScore: 2,
          teamBColorHex: TeamColorPalette.red,
          teamBName: "Swifts",
          teamBScore: 0
        ),
        GameListItem(
          endedAt: Date(timeIntervalSince1970: 1_500),
          id: UUID(-2),
          startedAt: olderDate,
          teamAColorHex: "#34C759",
          teamAName: "Foxes",
          teamAScore: 0,
          teamBColorHex: "#FF9500",
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
        Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
        Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
        Game(
          id: UUID(-1),
          startedAt: Date(timeIntervalSince1970: 1_000),
          endedAt: nil,
          teamAID: UUID(-1),
          teamBID: UUID(-2),
          periodDurationSeconds: 900,
          firstBreakDurationSeconds: 240,
          halfTimeDurationSeconds: 600,
          secondBreakDurationSeconds: 240
        )
      }
    }

    let game = try await database.read { db in
      try Game.find(UUID(-1)).fetchOne(db)
    }
    expectNoDifference(game?.currentPeriod, 1)
    expectNoDifference(game?.elapsedSeconds, 0)
    expectNoDifference(game?.hasTimerStartedCurrentPeriod, false)
    expectNoDifference(game?.isAwaitingCentrePassConfirmation, false)
    expectNoDifference(game?.centrePassTeamID, nil)

    let snapshot = try await database.read { db in
      try GameSnapshot.fetch(db, gameID: UUID(-1))
    }
    expectNoDifference(ScoringFeature.State(snapshot: snapshot).centrePassTeamID, UUID(-1))
  }

  @Test
  func breakSnapshotRehydratesPausedInTheCompletedQuartersOrder() {
    let ravens = Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
    let swifts = Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
    let snapshot = GameSnapshot(
      game: Game(
        id: UUID(-3),
        startedAt: Date(timeIntervalSince1970: 1_000),
        endedAt: nil,
        teamAID: ravens.id,
        teamBID: swifts.id,
        centrePassTeamID: ravens.id,
        periodDurationSeconds: 900,
        firstBreakDurationSeconds: 240,
        halfTimeDurationSeconds: 600,
        secondBreakDurationSeconds: 240,
        isInBreak: true,
        isAwaitingCentrePassConfirmation: true,
        currentPeriod: 2,
        elapsedSeconds: 125,
        hasTimerStartedCurrentPeriod: true
      ),
      goals: [],
      teamA: ravens,
      teamB: swifts
    )

    let state = ScoringFeature.State(snapshot: snapshot)
    expectNoDifference(state.clockPhase, .breakTime)
    expectNoDifference(state.currentDurationSeconds, 600)
    expectNoDifference(state.elapsedSeconds, 125)
    expectNoDifference(state.isShowingLastCentrePassBanner, true)
    expectNoDifference(state.isShowingOriginalTeamOrder, false)
    expectNoDifference(state.isTimerRunning, false)
  }

  @Test
  func teamIdentityUsesStableUnicodeNormalizationAndCanonicalColor() {
    let team = Team(id: UUID(50), name: "  E\u{301}CLAIRS  ", colorHex: "#abcdef")

    expectNoDifference(team.name, "E\u{301}CLAIRS")
    expectNoDifference(team.normalizedName, "éclairs")
    expectNoDifference(team.colorHex, "#ABCDEF")
    expectNoDifference(Team.normalizeName("Éclairs"), team.normalizedName)
  }

  @Test
  func normalizedTeamNameIndexRejectsDuplicateProfiles() async throws {
    @Dependency(\.defaultDatabase) var database
    try Self.clearDatabase(database)

    try await database.write { db in
      try Team.insert {
        Team(id: UUID(51), name: "Éclairs")
      }
      .execute(db)
    }

    do {
      try await database.write { db in
        try Team.insert {
          Team(id: UUID(52), name: "  E\u{301}CLAIRS ")
        }
        .execute(db)
      }
      Issue.record("Expected normalized team names to be unique")
    } catch {
      // The unique index is the final transactional guard against concurrent duplicates.
    }

    let teams = try await database.read { db in
      try Team.fetchAll(db)
    }
    expectNoDifference(teams.map(\.id), [UUID(51)])
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
    expectNoDifference(first.centrePassTeamID, UUID(-1))
    expectNoDifference(first.isTimerRunning, false)
    expectNoDifference(second.period, 2)
    expectNoDifference(second.elapsedSeconds, 75)
    expectNoDifference(second.teamAScore, 2)
    expectNoDifference(second.teamBScore, 0)
    expectNoDifference(second.canUndo, true)
    expectNoDifference(second.centrePassTeamID, UUID(-3))
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
        Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
        Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
        Game(
          id: UUID(-1),
          startedAt: startedAt,
          endedAt: endedAt,
          teamAID: UUID(-1),
          teamBID: UUID(-2),
          periodDurationSeconds: 900,
          firstBreakDurationSeconds: 240,
          halfTimeDurationSeconds: 600,
          secondBreakDurationSeconds: 240
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
        firstBreakDurationSeconds: 240,
        goals: [
          GoalTimelineItem(
            clockSecondsRemaining: 800,
            id: UUID(-1),
            period: 1,
            points: 2,
            scoringTeamColorHex: TeamColorPalette.blue,
            scoringTeamName: "Ravens",
            teamAScore: 2,
            teamBScore: 0
          ),
          GoalTimelineItem(
            clockSecondsRemaining: 700,
            id: UUID(-2),
            period: 1,
            points: 1,
            scoringTeamColorHex: TeamColorPalette.red,
            scoringTeamName: "Swifts",
            teamAScore: 2,
            teamBScore: 1
          ),
          GoalTimelineItem(
            clockSecondsRemaining: 870,
            id: UUID(-3),
            period: 2,
            points: 1,
            scoringTeamColorHex: TeamColorPalette.red,
            scoringTeamName: "Swifts",
            teamAScore: 2,
            teamBScore: 2
          ),
        ],
        halfTimeDurationSeconds: 600,
        id: UUID(-1),
        periodDurationSeconds: 900,
        secondBreakDurationSeconds: 240,
        startedAt: startedAt,
        teamAColorHex: TeamColorPalette.blue,
        teamAName: "Ravens",
        teamAScore: 2,
        teamBColorHex: TeamColorPalette.red,
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
            centrePassTeamID: state.centrePassTeamID,
            periodDurationSeconds: state.periodDurationSeconds,
            firstBreakDurationSeconds: state.firstBreakDurationSeconds,
            halfTimeDurationSeconds: state.halfTimeDurationSeconds,
            secondBreakDurationSeconds: state.secondBreakDurationSeconds,
            isInBreak: state.clockPhase == .breakTime,
            isAwaitingCentrePassConfirmation: state.isShowingLastCentrePassBanner,
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
      centrePassTeamID: UUID(1),
      gameID: UUID(3),
      startedAt: Date(timeIntervalSince1970: 500),
      teamA: ScoringFeature.Team(
        id: UUID(1),
        colorHex: TeamColorPalette.blue,
        name: "Ravens"
      ),
      teamB: ScoringFeature.Team(
        id: UUID(2),
        colorHex: TeamColorPalette.red,
        name: "Swifts"
      )
    )
  }

  private static func setupState(
    leftName: String,
    rightName: String
  ) -> SetupFeature.State {
    var state = SetupFeature.State()
    state.leftTeam.mode = .locked
    state.leftTeam.selection = .new(
      TeamSlotFeature.TeamDraft(
        colorHex: TeamColorPalette.blue,
        name: leftName
      )
    )
    state.rightTeam.mode = .locked
    state.rightTeam.selection = .new(
      TeamSlotFeature.TeamDraft(
        colorHex: TeamColorPalette.red,
        name: rightName
      )
    )
    return state
  }
}
