import Clocks
import ComposableArchitecture
import ConcurrencyExtras
import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import GRDB
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
  func alarmOnboardingAppearsWhenAuthorizationIsNotDetermined() async {
    let statusChecks = LockIsolated(0)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.alarmAuthorization = AlarmAuthorizationClient(
        request: { .notDetermined },
        status: {
          statusChecks.withValue { $0 += 1 }
          return .notDetermined
        }
      )
    }

    await store.send(.task) {
      $0.alarmOnboarding = AlarmOnboardingFeature.State()
      $0.hasCheckedAlarmAuthorization = true
    }
    await store.send(.task)

    expectNoDifference(statusChecks.value, 1)
  }

  @Test
  func alarmOnboardingIsSkippedWhenAuthorizationIsResolved() async {
    for expectedStatus in [AlarmAuthorizationStatus.authorized, .denied] {
      let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
      } withDependencies: {
        $0.alarmAuthorization = AlarmAuthorizationClient(
          request: { expectedStatus },
          status: { expectedStatus }
        )
      }

      await store.send(.task) {
        $0.hasCheckedAlarmAuthorization = true
      }
      expectNoDifference(store.state.alarmOnboarding, nil)
    }
  }

  @Test
  func alarmOnboardingCompletesAfterAuthorizationIsResolved() async {
    for expectedStatus in [AlarmAuthorizationStatus.authorized, .denied] {
      let requests = LockIsolated(0)
      let store = TestStore(initialState: AlarmOnboardingFeature.State()) {
        AlarmOnboardingFeature()
      } withDependencies: {
        $0.alarmAuthorization = AlarmAuthorizationClient(
          request: {
            requests.withValue { $0 += 1 }
            return expectedStatus
          },
          status: { expectedStatus }
        )
      }

      await store.send(.allowAlarmsButtonTapped) {
        $0.isRequesting = true
      }
      await store.receive {
        guard case let .authorizationResponse(.success(status)) = $0 else {
          return false
        }
        return status == expectedStatus
      } assert: {
        $0.isRequesting = false
      }
      await store.receive {
        guard case .delegate(.completed) = $0 else { return false }
        return true
      }

      expectNoDifference(requests.value, 1)
    }
  }

  @Test
  func alarmOnboardingCanBeSkippedWithoutRequestingAuthorization() async {
    let requests = LockIsolated(0)
    let store = TestStore(initialState: AlarmOnboardingFeature.State()) {
      AlarmOnboardingFeature()
    } withDependencies: {
      $0.alarmAuthorization = AlarmAuthorizationClient(
        request: {
          requests.withValue { $0 += 1 }
          return .authorized
        },
        status: { .notDetermined }
      )
    }

    await store.send(.notNowButtonTapped)
    await store.receive {
      guard case .delegate(.completed) = $0 else { return false }
      return true
    }

    expectNoDifference(requests.value, 0)
  }

  @Test
  func completingAlarmOnboardingRevealsGames() async {
    var state = AppFeature.State()
    state.alarmOnboarding = AlarmOnboardingFeature.State()
    state.hasCheckedAlarmAuthorization = true

    let store = TestStore(initialState: state) {
      AppFeature()
    }

    await store.send(.alarmOnboarding(.presented(.notNowButtonTapped)))
    await store.receive {
      guard case .alarmOnboarding(.presented(.delegate(.completed))) = $0 else {
        return false
      }
      return true
    } assert: {
      $0.alarmOnboarding = nil
    }
  }

  @Test
  func alarmOnboardingRequestFailureCanBeRetried() async {
    let attempts = LockIsolated(0)
    let store = TestStore(initialState: AlarmOnboardingFeature.State()) {
      AlarmOnboardingFeature()
    } withDependencies: {
      $0.alarmAuthorization = AlarmAuthorizationClient(
        request: {
          let attempt = attempts.withValue {
            $0 += 1
            return $0
          }
          guard attempt > 1 else { throw AlarmAuthorizationTestError.failed }
          return .authorized
        },
        status: { .notDetermined }
      )
    }

    await store.send(.allowAlarmsButtonTapped) {
      $0.isRequesting = true
    }
    await store.receive {
      guard case .authorizationResponse(.failure) = $0 else { return false }
      return true
    } assert: {
      $0.errorMessage = "Supershot couldn’t request alarm access. Try again."
      $0.isRequesting = false
    }

    await store.send(.allowAlarmsButtonTapped) {
      $0.errorMessage = nil
      $0.isRequesting = true
    }
    await store.receive {
      guard case .authorizationResponse(.success(.authorized)) = $0 else {
        return false
      }
      return true
    } assert: {
      $0.isRequesting = false
    }
    await store.receive {
      guard case .delegate(.completed) = $0 else { return false }
      return true
    }

    expectNoDifference(attempts.value, 2)
  }

  @Test
  func deletingGameRemovesGoalsRetainsTeamsAndEndsPresentation() async throws {
    let seedStore = Self.makeScoringStore()
    let database = seedStore.dependencies.defaultDatabase
    let events = LockIsolated<[TimerSystemEvent]>([])
    try await database.write { db in
      try Goal.insert {
        Goal(
          id: UUID(4),
          gameID: UUID(3),
          teamID: UUID(1),
          period: 1,
          elapsedSeconds: 10,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_000)
        )
      }
      .execute(db)
    }

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.defaultDatabase = database
      $0.gameTimer = .live(system: Self.timerSystemClient(events: events))
    }

    await store.send(.deleteGameButtonTapped(UUID(3))) {
      $0.deletingGameID = UUID(3)
    }
    await store.receive {
      guard case let .deleteGameResponse(gameID, .success) = $0 else {
        return false
      }
      return gameID == UUID(3)
    } assert: {
      $0.deletingGameID = nil
    }

    let values = try await database.read { db in
      (
        try Game.find(UUID(3)).fetchOne(db),
        try Goal.where { $0.gameID.eq(UUID(3)) }.fetchAll(db),
        try Team.fetchAll(db)
      )
    }
    expectNoDifference(values.0, nil)
    expectNoDifference(values.1, [])
    expectNoDifference(values.2.count, 2)
    expectNoDifference(events.value, [.cancelAlarm, .endActivity])
  }

  @Test
  func detailDeleteButtonDelegatesDeletion() async {
    let store = TestStore(initialState: GameDetailFeature.State(gameID: UUID(3))) {
      GameDetailFeature()
    }

    await store.send(.deleteButtonTapped)
    await store.receive(.delegate(.deleteGameButtonTapped))
  }

  @Test
  func deletingTeamRemovesItsGamesAndGoalsAndEndsPresentations() async throws {
    let seedStore = Self.makeScoringStore()
    let database = seedStore.dependencies.defaultDatabase
    let events = LockIsolated<[TimerSystemEvent]>([])
    try await database.write { db in
      try Goal.insert {
        Goal(
          id: UUID(4),
          gameID: UUID(3),
          teamID: UUID(1),
          period: 1,
          elapsedSeconds: 10,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_000)
        )
      }
      .execute(db)
    }

    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.defaultDatabase = database
      $0.gameTimer = .live(system: Self.timerSystemClient(events: events))
    }

    await store.send(.deleteTeamButtonTapped(UUID(1))) {
      $0.deletingTeamID = UUID(1)
    }
    await store.receive {
      guard case let .deleteTeamResponse(teamID, .success) = $0 else {
        return false
      }
      return teamID == UUID(1)
    } assert: {
      $0.deletingTeamID = nil
    }

    let values = try await database.read { db in
      (
        try Team.find(UUID(1)).fetchOne(db),
        try Game.find(UUID(3)).fetchOne(db),
        try Goal.where { $0.gameID.eq(UUID(3)) }.fetchAll(db),
        try Team.find(UUID(2)).fetchOne(db)
      )
    }
    expectNoDifference(values.0, nil)
    expectNoDifference(values.1, nil)
    expectNoDifference(values.2, [])
    expectNoDifference(values.3?.name, "Swifts")
    expectNoDifference(events.value, [.cancelAlarm, .endActivity])
  }

  @Test
  func setupValidationRequiresDifferentTeamNames() async {
    let state = Self.setupState(leftName: "Ravens", rightName: "Ravens")

    let store = TestStore(initialState: state) {
      NewGameFeature()
    }

    await store.send(.startGameButtonTapped) {
      $0.errorMessage = "Team names must be unique."
    }
  }

  @Test
  func setupValidationRequiresFirstCentrePass() async {
    let state = Self.setupState(leftName: "Ravens", rightName: "Swifts")

    let store = TestStore(initialState: state) {
      NewGameFeature()
    }

    await store.send(.startGameButtonTapped) {
      $0.errorMessage = "Choose the team taking the first centre pass."
    }
  }

  @Test
  func setupAllowsMatchingBibColors() {
    var state = Self.setupState(leftName: "Ravens", rightName: "Swifts")
    state.firstCentrePass = .teamA
    state.leftTeam.bibColorHex = "#34C759"
    state.rightTeam.bibColorHex = "#34C759"

    expectNoDifference(state.canStartGame, true)
  }

  @Test
  func startGameCreatesTeamsAndGame() async throws {
    var state = Self.setupState(leftName: "Ravens", rightName: "Swifts")
    state.firstCentrePass = .teamB
    state.leftTeam.bibColorHex = "#AF52DE"
    state.rightTeam.bibColorHex = "#FF2D55"

    let startedAt = Date(timeIntervalSince1970: 1_000)
    let store = TestStore(initialState: state) {
      NewGameFeature()
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
    expectNoDifference(games.first?.teamABibColorHex, "#AF52DE")
    expectNoDifference(games.first?.teamBBibColorHex, "#FF2D55")
    expectNoDifference(scoringState?.centrePassTeamID, scoringState?.teamB.id)
    expectNoDifference(scoringState?.teamA.name, "Ravens")
    expectNoDifference(scoringState?.teamB.name, "Swifts")
    expectNoDifference(scoringState?.teamA.bibColorHex, "#AF52DE")
    expectNoDifference(scoringState?.teamB.bibColorHex, "#FF2D55")
  }

  @Test
  func editingSavedTeamsIsStagedAndSupportsSafeNameSwaps() async throws {
    let ravens = Team(id: UUID(30), name: "Ravens", colorHex: TeamColorPalette.blue)
    let swifts = Team(id: UUID(31), name: "Swifts", colorHex: TeamColorPalette.red)
    var state = NewGameFeature.State()
    state.availableTeams = [ravens, swifts]
    state.firstCentrePass = .teamA
    state.leftTeam.mode = .locked
    state.leftTeam.selection = .existing(
      original: ravens,
      draft: TeamSlotFeature.TeamDraft(teamColorHex: "#34C759", name: "Swifts")
    )
    state.rightTeam.mode = .locked
    state.rightTeam.selection = .existing(
      original: swifts,
      draft: TeamSlotFeature.TeamDraft(teamColorHex: "#FF9500", name: "Ravens")
    )

    let store = TestStore(initialState: state) {
      NewGameFeature()
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
        message: "Ravens will become Swifts in game history, and its team color will update. "
          + "Swifts will become Ravens in game history, and its team color will update."
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
      draft: TeamSlotFeature.TeamDraft(teamColorHex: ravens.colorHex, name: ravens.name)
    )
    state.bibColorHex = "#FF9500"
    let store = TestStore(initialState: state) {
      TeamSlotFeature()
    }

    await store.send(.editTeamButtonTapped) {
      $0.editor = TeamSlotFeature.TeamDraft(teamColorHex: ravens.colorHex, name: ravens.name)
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
      $0.editor.teamColorHex = "#34C759"
    }
    await store.send(.doneButtonTapped) {
      $0.mode = .locked
      $0.selection = .existing(
        original: ravens,
        draft: TeamSlotFeature.TeamDraft(teamColorHex: "#34C759", name: "Falcons")
      )
    }
    await store.send(.revertChangesButtonTapped) {
      $0.selection = .existing(
        original: ravens,
        draft: TeamSlotFeature.TeamDraft(teamColorHex: ravens.colorHex, name: ravens.name)
      )
    }
    expectNoDifference(store.state.bibColorHex, "#FF9500")
  }

  @Test
  func emptyTeamCardOffersExistingTeamsAndCreateFlow() async {
    let ravens = Team(id: UUID(20), name: "Ravens", colorHex: "#AF52DE")
    var state = NewGameFeature.State()
    state.availableTeams = [ravens]
    let store = TestStore(initialState: state) {
      NewGameFeature()
    } withDependencies: {
      $0.withRandomNumberGenerator = .init(ZeroRandomNumberGenerator())
    }

    await store.send(.leftTeam(.cardTapped)) {
      $0.leftTeam.mode = .choosing
    }
    await store.send(.leftTeam(.existingTeamSelected(ravens))) {
      $0.leftTeam.bibColorHex = "#AF52DE"
      $0.leftTeam.mode = .locked
      $0.leftTeam.selection = .existing(
        original: ravens,
        draft: TeamSlotFeature.TeamDraft(
          teamColorHex: "#AF52DE",
          name: "Ravens"
        )
      )
    }

    await store.send(.rightTeam(.cardTapped)) {
      $0.rightTeam.mode = .choosing
    }
    await store.send(.rightTeam(.createTeamButtonTapped)) {
      $0.rightTeam.editor.teamColorHex = TeamColorPalette.blue
      $0.rightTeam.mode = .creating
    }
    await store.send(.rightTeam(.binding(.set(\.editor.name, "Falcons")))) {
      $0.rightTeam.editor.name = "Falcons"
    }
    await store.send(.rightTeam(.paletteColorButtonTapped("#34C759"))) {
      $0.rightTeam.editor.teamColorHex = "#34C759"
    }
    await store.send(.rightTeam(.doneButtonTapped)) {
      $0.rightTeam.bibColorHex = "#34C759"
      $0.rightTeam.mode = .locked
      $0.rightTeam.selection = .new(
        TeamSlotFeature.TeamDraft(teamColorHex: "#34C759", name: "Falcons")
      )
    }
    await store.send(.rightTeam(.bibPaletteColorButtonTapped("#FF3B30"))) {
      $0.rightTeam.bibColorHex = "#FF3B30"
    }
    expectNoDifference(store.state.rightTeam.selectedDraft?.teamColorHex, "#34C759")
  }

  @Test
  func swappingTeamsSwapsCompleteSelectionsAndFirstCentrePass() async {
    var state = Self.setupState(leftName: "Ravens", rightName: "Swifts")
    state.firstCentrePass = .teamA
    state.leftTeam.bibColorHex = "#AF52DE"
    state.rightTeam.bibColorHex = "#FF9500"
    let store = TestStore(initialState: state) {
      NewGameFeature()
    }

    await store.send(.swapTeamsButtonTapped) {
      let leftSelection = $0.leftTeam.selection
      let leftBibColorHex = $0.leftTeam.bibColorHex
      $0.leftTeam.selection = $0.rightTeam.selection
      $0.leftTeam.bibColorHex = $0.rightTeam.bibColorHex
      $0.rightTeam.selection = leftSelection
      $0.rightTeam.bibColorHex = leftBibColorHex
      $0.firstCentrePass = .teamB
    }

    expectNoDifference(store.state.leftTeam.selectedDraft?.name, "Swifts")
    expectNoDifference(store.state.leftTeam.selectedDraft?.teamColorHex, TeamColorPalette.red)
    expectNoDifference(store.state.rightTeam.selectedDraft?.name, "Ravens")
    expectNoDifference(store.state.rightTeam.selectedDraft?.teamColorHex, TeamColorPalette.blue)
    expectNoDifference(store.state.leftTeam.bibColorHex, "#FF9500")
    expectNoDifference(store.state.rightTeam.bibColorHex, "#AF52DE")
  }

  @Test
  func breakDurationsCanBeUniformOrCustomized() async {
    let store = TestStore(initialState: NewGameFeature.State()) {
      NewGameFeature()
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
  func runningTimerMigrationLeavesExistingProgressPaused() throws {
    let database = try DatabaseQueue()
    try database.write { db in
      try db.execute(
        sql: """
          CREATE TABLE "games"(
            "id" TEXT PRIMARY KEY NOT NULL,
            "elapsedSeconds" INTEGER NOT NULL
          ) STRICT
          """
      )
      try db.execute(
        sql: "INSERT INTO \"games\" (\"id\", \"elapsedSeconds\") VALUES (?, ?)",
        arguments: [UUID(3).uuidString, 42]
      )

      try migrateAddRunningTimerEndDate(db)

      let row = try Row.fetchOne(
        db,
        sql: "SELECT \"elapsedSeconds\", \"timerEndsAt\" FROM \"games\""
      )
      expectNoDifference(row?["elapsedSeconds"] as Int?, 42)
      expectNoDifference(row?["timerEndsAt"] as String?, nil)
    }
  }

  @Test
  func perGameBibColorMigrationSnapshotsTeamColorsAndUsesFallbacks() throws {
    let database = try DatabaseQueue()
    try database.write { db in
      try db.execute(
        sql: """
          CREATE TABLE "teams"(
            "id" TEXT PRIMARY KEY NOT NULL,
            "colorHex" TEXT NOT NULL
          ) STRICT
          """
      )
      try db.execute(
        sql: """
          CREATE TABLE "games"(
            "id" TEXT PRIMARY KEY NOT NULL,
            "teamAID" TEXT NOT NULL,
            "teamBID" TEXT NOT NULL
          ) STRICT
          """
      )
      try db.execute(
        sql: "INSERT INTO \"teams\" (\"id\", \"colorHex\") VALUES (?, ?), (?, ?)",
        arguments: [
          UUID(1).uuidString, "#34C759",
          UUID(2).uuidString, "#FF9500",
        ]
      )
      try db.execute(
        sql: "INSERT INTO \"games\" (\"id\", \"teamAID\", \"teamBID\") VALUES (?, ?, ?), (?, ?, ?)",
        arguments: [
          UUID(3).uuidString, UUID(1).uuidString, UUID(2).uuidString,
          UUID(4).uuidString, UUID(5).uuidString, UUID(6).uuidString,
        ]
      )

      try migrateAddPerGameBibColors(db)

      let rows = try Row.fetchAll(
        db,
        sql: "SELECT \"teamABibColorHex\", \"teamBBibColorHex\" FROM \"games\" ORDER BY \"id\""
      )
      expectNoDifference(rows[0]["teamABibColorHex"] as String?, "#34C759")
      expectNoDifference(rows[0]["teamBBibColorHex"] as String?, "#FF9500")
      expectNoDifference(rows[1]["teamABibColorHex"] as String?, TeamColorPalette.blue)
      expectNoDifference(rows[1]["teamBBibColorHex"] as String?, TeamColorPalette.red)

      try db.execute(
        sql: "UPDATE \"teams\" SET \"colorHex\" = '#AF52DE'"
      )
      let unchangedRow = try Row.fetchOne(
        db,
        sql: "SELECT \"teamABibColorHex\", \"teamBBibColorHex\" FROM \"games\" WHERE \"id\" = ?",
        arguments: [UUID(3).uuidString]
      )
      expectNoDifference(unchangedRow?["teamABibColorHex"] as String?, "#34C759")
      expectNoDifference(unchangedRow?["teamBBibColorHex"] as String?, "#FF9500")
    }
  }

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

    await store.send(.resumeTimerButtonTapped) {
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

  @Test
  func timerStartsPausesAndResumes() async throws {
    let clock = TestClock()
    let store = Self.makeScoringStore(clock: clock)

    await store.send(.startTimerButtonTapped) {
      $0.hasTimerStartedThisPeriod = true
      $0.isTimerRunning = true
      $0.timerEndsAt = Date(timeIntervalSince1970: 1_900)
    }
    await store.receive {
      guard case .timerStartResponse(.success) = $0 else { return false }
      return true
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
      $0.timerEndsAt = nil
    }
    await store.receive {
      guard case .timerPauseResponse(.success) = $0 else { return false }
      return true
    }

    await store.send(.resumeTimerButtonTapped) {
      $0.isTimerRunning = true
      $0.timerEndsAt = Date(timeIntervalSince1970: 1_900)
    }
    await store.receive {
      guard case .timerStartResponse(.success) = $0 else { return false }
      return true
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
      $0.timerEndsAt = nil
    }
    await store.receive {
      guard case .timerPauseResponse(.success) = $0 else { return false }
      return true
    }
    await store.finish()
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
      $0.timerEndsAt = Date(timeIntervalSince1970: 1_001)
    }
    await store.receive {
      guard case .timerStartResponse(.success) = $0 else { return false }
      return true
    }

    await clock.advance(by: .seconds(1))
    await store.receive {
      guard case .timerTick = $0 else { return false }
      return true
    } assert: {
      $0.elapsedSeconds = $0.periodDurationSeconds
      $0.isTimerRunning = false
      $0.timerEndsAt = nil
    }
    await store.receive {
      guard case .timerReconcileResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.isShowingLastCentrePassBanner = true
    }
    await store.finish()
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
    await store.finish()
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
    await store.finish()
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
    await store.finish()
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
      $0.timerEndsAt = Date(timeIntervalSince1970: 1_002)
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
      $0.timerEndsAt = nil
    }
    await store.receive {
      guard case .timerReconcileResponse(.success) = $0 else { return false }
      return true
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
    await store.finish()
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
    await store.finish()
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
    await store.finish()
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
      $0.timerEndsAt = Date(timeIntervalSince1970: 1_001)
    }
    await store.receive {
      guard case .timerStartResponse(.success) = $0 else { return false }
      return true
    }
    await clock.advance(by: .seconds(1))
    await store.receive {
      guard case .timerTick = $0 else { return false }
      return true
    } assert: {
      $0.elapsedSeconds = $0.periodDurationSeconds
      $0.isTimerRunning = false
      $0.timerEndsAt = nil
    }
    await store.receive {
      guard case .timerReconcileResponse(.success) = $0 else { return false }
      return true
    }

    expectNoDifference(store.state.clockPhase, .quarter)
    expectNoDifference(store.state.canFinishGame, true)
    await store.finish()
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
    await store.finish()
  }

  @Test
  func runningGoalUsesAuthoritativeEndDateForTimestamp() async throws {
    var state = Self.scoringState()
    state.elapsedSeconds = 123
    state.hasTimerStartedThisPeriod = true
    state.isTimerRunning = true
    state.timerEndsAt = Date(timeIntervalSince1970: 1_200)
    let store = Self.makeScoringStore(state: state)

    await store.send(.goalButtonTapped(UUID(1))) {
      $0.elapsedSeconds = 700
    }
    await store.receive {
      guard case .goalResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.canUndo = true
      $0.centrePassTeamID = UUID(2)
      $0.teamAScore = 1
    }

    let goal = try await store.dependencies.defaultDatabase.read { db in
      try Goal.fetchOne(db)
    }
    expectNoDifference(goal?.elapsedSeconds, 700)
    await store.finish()
  }

  @Test
  func backgroundingLeavesAuthoritativeTimerRunning() async throws {
    let clock = TestClock()
    let store = Self.makeScoringStore(clock: clock)

    await store.send(.startTimerButtonTapped) {
      $0.hasTimerStartedThisPeriod = true
      $0.isTimerRunning = true
      $0.timerEndsAt = Date(timeIntervalSince1970: 1_900)
    }
    await store.receive {
      guard case .timerStartResponse(.success) = $0 else { return false }
      return true
    }

    await clock.advance(by: .seconds(1))
    await store.receive {
      guard case .timerTick = $0 else { return false }
      return true
    } assert: {
      $0.elapsedSeconds = 1
    }

    await store.send(.sceneBecameInactive)
    await clock.advance(by: .seconds(119))
    await store.send(.sceneBecameActive)
    await store.receive {
      guard case .timerReconcileResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.elapsedSeconds = 120
    }
    await clock.advance(by: .seconds(1))
    await store.receive {
      guard case .timerTick = $0 else { return false }
      return true
    } assert: {
      $0.elapsedSeconds = 121
    }
    await store.send(.sceneBecameInactive)
    await store.finish()

    let snapshot = try await store.dependencies.defaultDatabase.read { db in
      try GameSnapshot.fetch(db, gameID: UUID(3))
    }
    expectNoDifference(snapshot.game.currentPeriod, 1)
    expectNoDifference(snapshot.game.elapsedSeconds, 0)
    expectNoDifference(snapshot.game.hasTimerStartedCurrentPeriod, true)
    expectNoDifference(snapshot.game.centrePassTeamID, UUID(1))
    expectNoDifference(
      snapshot.game.timerEndsAt,
      Date(timeIntervalSince1970: 1_900)
    )
    expectNoDifference(store.state.elapsedSeconds, 121)
    expectNoDifference(store.state.isTimerRunning, true)
  }

  @Test
  func leavingScoringKeepsTimerRunningAndDismisses() async throws {
    let didDismiss = LockIsolated(false)
    var state = Self.scoringState()
    state.elapsedSeconds = 123
    state.hasTimerStartedThisPeriod = true
    state.isTimerRunning = true
    state.period = 2
    state.timerEndsAt = Date(timeIntervalSince1970: 1_777)
    let store = Self.makeScoringStore(
      state: state,
      dismiss: DismissEffect { didDismiss.setValue(true) }
    )

    await store.send(.closeButtonTapped)
    await store.finish()

    let game = try await store.dependencies.defaultDatabase.read { db in
      try Game.find(UUID(3)).fetchOne(db)
    }
    expectNoDifference(didDismiss.value, true)
    expectNoDifference(game?.currentPeriod, 2)
    expectNoDifference(game?.elapsedSeconds, 123)
    expectNoDifference(game?.hasTimerStartedCurrentPeriod, true)
    expectNoDifference(game?.centrePassTeamID, UUID(1))
    expectNoDifference(game?.timerEndsAt, Date(timeIntervalSince1970: 1_777))
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
    expectNoDifference(goals.first?.centrePassTeamID, UUID(1))
    expectNoDifference(goals.first?.teamID, UUID(1))
    expectNoDifference(goals.first?.period, 1)
    expectNoDifference(goals.first?.elapsedSeconds, 0)
    await store.finish()
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
    await store.finish()
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

    let goal = try await store.dependencies.defaultDatabase.read { db in
      try Goal.fetchOne(db)
    }
    expectNoDifference(goal?.centrePassTeamID, UUID(2))
    await store.finish()
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
          teamABibColorHex: "#34C759",
          teamBID: UUID(-4),
          teamBBibColorHex: "#FF9500",
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
          teamABibColorHex: TeamColorPalette.blue,
          teamAName: "Ravens",
          teamAScore: 2,
          teamBBibColorHex: TeamColorPalette.red,
          teamBName: "Swifts",
          teamBScore: 0
        ),
        GameListItem(
          endedAt: Date(timeIntervalSince1970: 1_500),
          id: UUID(-2),
          startedAt: olderDate,
          teamABibColorHex: "#34C759",
          teamAName: "Foxes",
          teamAScore: 0,
          teamBBibColorHex: "#FF9500",
          teamBName: "Owls",
          teamBScore: 1
        ),
      ]
    )
  }

  @Test
  func gameHistoryKeepsBibColorsAfterTeamProfileColorsChange() async throws {
    @Dependency(\.defaultDatabase) var database
    try Self.clearDatabase(database)

    let startedAt = Date(timeIntervalSince1970: 1_000)
    let updatedRavensColorHex = "#34C759"
    let updatedSwiftsColorHex = "#FF2D55"
    try await database.write { db in
      try db.seed {
        Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
        Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
        Game(
          id: UUID(-1),
          startedAt: startedAt,
          endedAt: Date(timeIntervalSince1970: 2_000),
          teamAID: UUID(-1),
          teamABibColorHex: "#AF52DE",
          teamBID: UUID(-2),
          teamBBibColorHex: "#FF9500",
          periodDurationSeconds: 900
        )
        Game(
          id: UUID(-2),
          startedAt: Date(timeIntervalSince1970: 3_000),
          endedAt: nil,
          teamAID: UUID(-1),
          teamABibColorHex: "#30B0C7",
          teamBID: UUID(-2),
          teamBBibColorHex: "#FF2D55",
          periodDurationSeconds: 900
        )
        Goal(
          id: UUID(-1),
          gameID: UUID(-1),
          teamID: UUID(-1),
          period: 1,
          elapsedSeconds: 20,
          points: 1,
          createdAt: startedAt
        )
      }
      try Team.find(UUID(-1)).update {
        $0.colorHex = #bind(updatedRavensColorHex)
      }
      .execute(db)
      try Team.find(UUID(-2)).update {
        $0.colorHex = #bind(updatedSwiftsColorHex)
      }
      .execute(db)
    }

    let values = try await database.read { db in
      (
        try GamesRequest().fetch(db),
        try TeamsRequest().fetch(db),
        try GameDetailRequest(gameID: UUID(-1)).fetch(db)
      )
    }

    expectNoDifference(values.0.games.map(\.teamABibColorHex), ["#30B0C7", "#AF52DE"])
    expectNoDifference(values.0.games.map(\.teamBBibColorHex), ["#FF2D55", "#FF9500"])
    expectNoDifference(values.1.teams.map(\.colorHex), ["#34C759", "#FF2D55"])
    expectNoDifference(values.2.detail?.teamABibColorHex, "#AF52DE")
    expectNoDifference(values.2.detail?.teamBBibColorHex, "#FF9500")
    expectNoDifference(
      values.2.detail?.goalTimeline.quarters.last?.goals.first?.scoringTeamBibColorHex,
      "#AF52DE"
    )
  }

  @Test
  func teamsListIsAlphabeticalWithGameCounts() async throws {
    @Dependency(\.defaultDatabase) var database
    try Self.clearDatabase(database)

    try await database.write { db in
      try db.seed {
        Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
        Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
        Team(id: UUID(-3), name: "Aces", colorHex: "#34C759")
        Game(
          id: UUID(-1),
          startedAt: Date(timeIntervalSince1970: 1_000),
          endedAt: nil,
          teamAID: UUID(-1),
          teamBID: UUID(-2),
          periodDurationSeconds: 900
        )
        Game(
          id: UUID(-2),
          startedAt: Date(timeIntervalSince1970: 2_000),
          endedAt: Date(timeIntervalSince1970: 3_000),
          teamAID: UUID(-3),
          teamBID: UUID(-1),
          periodDurationSeconds: 900
        )
      }
    }

    let value = try await database.read { db in
      try TeamsRequest().fetch(db)
    }

    expectNoDifference(
      value.teams,
      [
        TeamListItem(
          colorHex: "#34C759",
          gameCount: 1,
          id: UUID(-3),
          name: "Aces"
        ),
        TeamListItem(
          colorHex: TeamColorPalette.blue,
          gameCount: 2,
          id: UUID(-1),
          name: "Ravens"
        ),
        TeamListItem(
          colorHex: TeamColorPalette.red,
          gameCount: 1,
          id: UUID(-2),
          name: "Swifts"
        ),
      ]
    )
  }

  @Test
  func teamDetailShowsOnlyTheTeamsGamesNewestFirst() async throws {
    @Dependency(\.defaultDatabase) var database
    try Self.clearDatabase(database)

    let olderDate = Date(timeIntervalSince1970: 1_000)
    let newerDate = Date(timeIntervalSince1970: 2_000)
    try await database.write { db in
      try db.seed {
        Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
        Team(id: UUID(-2), name: "Swifts", colorHex: TeamColorPalette.red)
        Team(id: UUID(-3), name: "Aces", colorHex: "#34C759")
        Game(
          id: UUID(-1),
          startedAt: olderDate,
          endedAt: Date(timeIntervalSince1970: 1_500),
          teamAID: UUID(-1),
          teamBID: UUID(-2),
          periodDurationSeconds: 900
        )
        Game(
          id: UUID(-2),
          startedAt: newerDate,
          endedAt: nil,
          teamAID: UUID(-3),
          teamABibColorHex: "#34C759",
          teamBID: UUID(-1),
          teamBBibColorHex: TeamColorPalette.blue,
          periodDurationSeconds: 600
        )
        Game(
          id: UUID(-3),
          startedAt: Date(timeIntervalSince1970: 3_000),
          endedAt: nil,
          teamAID: UUID(-2),
          teamBID: UUID(-3),
          periodDurationSeconds: 900
        )
        Goal(
          id: UUID(-1),
          gameID: UUID(-1),
          teamID: UUID(-1),
          period: 1,
          elapsedSeconds: 10,
          points: 2,
          createdAt: olderDate
        )
        Goal(
          id: UUID(-2),
          gameID: UUID(-2),
          teamID: UUID(-3),
          period: 1,
          elapsedSeconds: 20,
          points: 1,
          createdAt: newerDate
        )
      }
    }

    let value = try await database.read { db in
      try TeamDetailRequest(teamID: UUID(-1)).fetch(db)
    }

    expectNoDifference(
      value,
      TeamDetailRequest.Value(
        games: [
          GameListItem(
            endedAt: nil,
            id: UUID(-2),
            periodDurationSeconds: 600,
            startedAt: newerDate,
            teamABibColorHex: "#34C759",
            teamAName: "Aces",
            teamAScore: 1,
            teamBBibColorHex: TeamColorPalette.blue,
            teamBName: "Ravens",
            teamBScore: 0
          ),
          GameListItem(
            endedAt: Date(timeIntervalSince1970: 1_500),
            id: UUID(-1),
            startedAt: olderDate,
            teamABibColorHex: TeamColorPalette.blue,
            teamAName: "Ravens",
            teamAScore: 2,
            teamBBibColorHex: TeamColorPalette.red,
            teamBName: "Swifts",
            teamBScore: 0
          ),
        ],
        team: Team(
          id: UUID(-1),
          name: "Ravens",
          colorHex: TeamColorPalette.blue
        )
      )
    )
  }

  @Test
  func teamEditorTrimsAndPersistsNameAndColor() async throws {
    let team = Team(id: UUID(-1), name: "Ravens", colorHex: TeamColorPalette.blue)
    let store = TestStore(initialState: TeamEditorFeature.State(team: team)) {
      TeamEditorFeature()
    } withDependencies: {
      try! $0.bootstrapDatabase()
      try! Self.clearDatabase($0.defaultDatabase)
      try! $0.defaultDatabase.write { db in
        try Team.insert { team }.execute(db)
      }
    }

    await store.send(.binding(.set(\.name, "  Falcons  "))) {
      $0.name = "  Falcons  "
    }
    await store.send(.paletteColorButtonTapped("#34c759")) {
      $0.colorHex = "#34C759"
    }
    await store.send(.saveButtonTapped) {
      $0.errorMessage = nil
      $0.isSaving = true
      $0.name = "Falcons"
    }
    await store.receive {
      guard case .saveResponse(.success) = $0 else { return false }
      return true
    } assert: {
      $0.isSaving = false
    }
    await store.receive {
      guard case .delegate(.saved) = $0 else { return false }
      return true
    }

    let savedTeam = try await store.dependencies.defaultDatabase.read { db in
      try Team.find(team.id).fetchOne(db)
    }
    expectNoDifference(
      savedTeam,
      Team(id: team.id, name: "Falcons", colorHex: "#34C759")
    )
  }

  @Test
  func teamEditorRejectsDuplicateNormalizedName() async throws {
    let ravens = Team(id: UUID(-1), name: "Ravens")
    let swifts = Team(id: UUID(-2), name: "Swifts")
    let store = TestStore(initialState: TeamEditorFeature.State(team: ravens)) {
      TeamEditorFeature()
    } withDependencies: {
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

    await store.send(.binding(.set(\.name, "  SWIFTS "))) {
      $0.name = "  SWIFTS "
    }
    await store.send(.saveButtonTapped) {
      $0.errorMessage = nil
      $0.isSaving = true
      $0.name = "SWIFTS"
    }
    await store.receive {
      guard case .saveResponse(.failure) = $0 else { return false }
      return true
    } assert: {
      $0.errorMessage = "Team names must be unique."
      $0.isSaving = false
    }

    let savedTeam = try await store.dependencies.defaultDatabase.read { db in
      try Team.find(ravens.id).fetchOne(db)
    }
    expectNoDifference(savedTeam, ravens)
  }

  @Test
  func teamEditorReportsWhenTeamWasDeleted() async {
    let team = Team(id: UUID(-1), name: "Ravens")
    let store = TestStore(initialState: TeamEditorFeature.State(team: team)) {
      TeamEditorFeature()
    } withDependencies: {
      try! $0.bootstrapDatabase()
      try! Self.clearDatabase($0.defaultDatabase)
    }

    await store.send(.binding(.set(\.name, "Falcons"))) {
      $0.name = "Falcons"
    }
    await store.send(.saveButtonTapped) {
      $0.errorMessage = nil
      $0.isSaving = true
    }
    await store.receive {
      guard case .saveResponse(.failure) = $0 else { return false }
      return true
    } assert: {
      $0.errorMessage = "This team is no longer available."
      $0.isSaving = false
    }
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
          teamABibColorHex: "#AF52DE",
          teamBID: UUID(-2),
          teamBBibColorHex: "#FF9500",
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
    let state = ScoringFeature.State(snapshot: snapshot)
    expectNoDifference(state.centrePassTeamID, UUID(-1))
    expectNoDifference(state.teamA.bibColorHex, "#AF52DE")
    expectNoDifference(state.teamB.bibColorHex, "#FF9500")
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
  func completedGameDetailBuildsReverseChronologicalQuarterTimeline() async throws {
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
          centrePassTeamID: UUID(-2),
          teamID: UUID(-2),
          period: 2,
          elapsedSeconds: 30,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_300)
        )
        Goal(
          id: UUID(-1),
          gameID: UUID(-1),
          centrePassTeamID: UUID(-1),
          teamID: UUID(-1),
          period: 1,
          elapsedSeconds: 100,
          points: 2,
          createdAt: Date(timeIntervalSince1970: 1_100)
        )
        Goal(
          id: UUID(-2),
          gameID: UUID(-1),
          centrePassTeamID: UUID(-1),
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
        goalTimeline: GoalTimeline(
          quarters: [
            GoalTimelineQuarter(
              goals: [],
              period: 4,
              teamAQuarterScore: 0,
              teamBQuarterScore: 0
            ),
            GoalTimelineQuarter(
              goals: [],
              period: 3,
              teamAQuarterScore: 0,
              teamBQuarterScore: 0
            ),
            GoalTimelineQuarter(
              goals: [
                GoalTimelineItem(
                  clockSecondsRemaining: 870,
                  id: UUID(-3),
                  period: 2,
                  points: 1,
                  scoringTeamBibColorHex: TeamColorPalette.red,
                  scoringTeamName: "Swifts",
                  scoringTeamSide: .teamB,
                  teamAScore: 2,
                  teamBScore: 2
                )
              ],
              period: 2,
              teamAQuarterScore: 0,
              teamBQuarterScore: 1
            ),
            GoalTimelineQuarter(
              goals: [
                GoalTimelineItem(
                  clockSecondsRemaining: 700,
                  id: UUID(-2),
                  period: 1,
                  points: 1,
                  scoringTeamBibColorHex: TeamColorPalette.red,
                  scoringTeamName: "Swifts",
                  scoringTeamSide: .teamB,
                  teamAScore: 2,
                  teamBScore: 1
                ),
                GoalTimelineItem(
                  clockSecondsRemaining: 800,
                  id: UUID(-1),
                  period: 1,
                  points: 2,
                  scoringTeamBibColorHex: TeamColorPalette.blue,
                  scoringTeamName: "Ravens",
                  scoringTeamSide: .teamA,
                  teamAScore: 2,
                  teamBScore: 0
                ),
              ],
              period: 1,
              teamAQuarterScore: 2,
              teamBQuarterScore: 1
            ),
          ]
        ),
        halfTimeDurationSeconds: 600,
        id: UUID(-1),
        periodDurationSeconds: 900,
        secondBreakDurationSeconds: 240,
        startedAt: startedAt,
        statistics: CompletedGameStatistics(
          teamA: TeamGameStatistics(
            averageTimeToGoalSeconds: 100,
            centrePass: CentrePassStatistics(
              conversions: 1,
              inferredTurnovers: 1,
              opportunities: 2
            )
          ),
          teamB: TeamGameStatistics(
            averageTimeToGoalSeconds: 65,
            centrePass: CentrePassStatistics(
              conversions: 1,
              inferredTurnovers: 0,
              opportunities: 1
            )
          )
        ),
        teamABibColorHex: TeamColorPalette.blue,
        teamAName: "Ravens",
        teamAScore: 2,
        teamBBibColorHex: TeamColorPalette.red,
        teamBName: "Swifts",
        teamBScore: 2
      )
    )
  }

  @Test
  func liveGoalTimelineIncludesEmptyPlayedQuartersAndReflectsGoalChanges() async throws {
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
          currentPeriod: 3
        )
        Goal(
          id: UUID(-1),
          gameID: UUID(-1),
          teamID: UUID(-1),
          period: 1,
          elapsedSeconds: 100,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_100)
        )
      }
    }

    let initial = try await database.read { db in
      try GoalTimelineRequest(gameID: UUID(-1)).fetch(db).timeline
    }
    expectNoDifference(initial.quarters.map(\.period), [3, 2, 1])
    expectNoDifference(initial.quarters.map(\.goals.count), [0, 0, 1])
    expectNoDifference(initial.quarters.last?.teamAQuarterScore, 1)
    expectNoDifference(initial.quarters.last?.goals.first?.scoringTeamSide, .teamA)

    try await database.write { db in
      try Goal.insert {
        Goal(
          id: UUID(-2),
          gameID: UUID(-1),
          teamID: UUID(-2),
          period: 3,
          elapsedSeconds: 200,
          points: 2,
          createdAt: Date(timeIntervalSince1970: 1_200)
        )
      }
      .execute(db)
    }

    let afterGoal = try await database.read { db in
      try GoalTimelineRequest(gameID: UUID(-1)).fetch(db).timeline
    }
    expectNoDifference(afterGoal.quarters.first?.teamAQuarterScore, 0)
    expectNoDifference(afterGoal.quarters.first?.teamBQuarterScore, 2)
    expectNoDifference(afterGoal.quarters.first?.goals.first?.scoringTeamSide, .teamB)
    expectNoDifference(afterGoal.quarters.first?.goals.first?.teamAScore, 1)
    expectNoDifference(afterGoal.quarters.first?.goals.first?.teamBScore, 2)

    try await database.write { db in
      try Goal.find(UUID(-2)).delete().execute(db)
    }

    let afterUndo = try await database.read { db in
      try GoalTimelineRequest(gameID: UUID(-1)).fetch(db).timeline
    }
    expectNoDifference(afterUndo.quarters.first?.goals, [])
    expectNoDifference(afterUndo.quarters.first?.teamBQuarterScore, 0)
  }

  @Test
  func completedGameDetailKeepsLegacyCentrePassStatisticsUnavailable() async throws {
    @Dependency(\.defaultDatabase) var database
    try Self.clearDatabase(database)

    try await database.write { db in
      try db.seed {
        Team(id: UUID(-1), name: "Ravens")
        Team(id: UUID(-2), name: "Swifts")
        Game(
          id: UUID(-1),
          startedAt: Date(timeIntervalSince1970: 1_000),
          endedAt: Date(timeIntervalSince1970: 2_000),
          teamAID: UUID(-1),
          teamBID: UUID(-2),
          periodDurationSeconds: 900
        )
        Goal(
          id: UUID(-1),
          gameID: UUID(-1),
          teamID: UUID(-1),
          period: 1,
          elapsedSeconds: 42,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_042)
        )
      }
    }

    let detail = try await database.read { db in
      try GameDetailRequest(gameID: UUID(-1)).fetch(db).detail
    }

    expectNoDifference(
      detail?.statistics,
      CompletedGameStatistics(
        teamA: TeamGameStatistics(
          averageTimeToGoalSeconds: 42,
          centrePass: nil
        ),
        teamB: TeamGameStatistics(
          averageTimeToGoalSeconds: nil,
          centrePass: nil
        )
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

  @Test
  func gameDeepLinkReconcilesAndRestoresRunningScoringRoute() async {
    var scoring = Self.scoringState()
    scoring.hasTimerStartedThisPeriod = true
    scoring.isTimerRunning = true
    scoring.timerEndsAt = Date(timeIntervalSince1970: 1_900)
    let seedStore = Self.makeScoringStore(state: scoring)
    let database = seedStore.dependencies.defaultDatabase
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_100)
      $0.defaultDatabase = database
      $0.gameTimer = .live(system: .noop)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .deepLinkOpened(URL(string: "supershot://game/\(UUID(3).uuidString)")!)
    )
    await store.receive {
      guard case .resumeGameResponse(UUID(3), .success) = $0 else { return false }
      return true
    }

    expectNoDifference(store.state.path.count, 1)
    guard case let .scoring(restored) = store.state.path[0] else {
      Issue.record("Expected the running scoring route")
      return
    }
    expectNoDifference(restored.elapsedSeconds, 100)
    expectNoDifference(restored.isTimerRunning, true)
    expectNoDifference(
      restored.timerEndsAt,
      Date(timeIntervalSince1970: 1_900)
    )
  }

  @Test
  func tabsRetainIndependentNavigationHistories() async {
    var state = AppFeature.State()
    state.path.append(.setup(NewGameFeature.State()))
    state.teamsPath.append(
      .teamDetail(TeamDetailFeature.State(teamID: UUID(1)))
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    }

    await store.send(.selectedTabChanged(.teams)) {
      $0.selectedTab = .teams
    }

    expectNoDifference(store.state.path.count, 1)
    expectNoDifference(store.state.teamsPath.count, 1)
  }

  @Test
  func completedTeamGameOpensDetailInTeamsStack() async {
    let game = GameListItem(
      endedAt: Date(timeIntervalSince1970: 2_000),
      id: UUID(3),
      startedAt: Date(timeIntervalSince1970: 1_000),
      teamAName: "Ravens",
      teamAScore: 12,
      teamBName: "Swifts",
      teamBScore: 10
    )
    var state = AppFeature.State()
    state.selectedTab = .teams
    state.teamsPath.append(
      .teamDetail(TeamDetailFeature.State(teamID: UUID(1)))
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    }

    await store.send(.teamGameRowTapped(game)) {
      $0.teamsPath.append(
        .gameDetail(GameDetailFeature.State(gameID: game.id))
      )
    }

    expectNoDifference(store.state.path.count, 0)
    expectNoDifference(store.state.teamsPath.count, 2)
  }

  @Test
  func unfinishedTeamGameResumesAndFinishesInTeamsStack() async {
    let seedStore = Self.makeScoringStore()
    let database = seedStore.dependencies.defaultDatabase
    let game = GameListItem(
      endedAt: nil,
      id: UUID(3),
      startedAt: Date(timeIntervalSince1970: 500),
      teamAName: "Ravens",
      teamAScore: 0,
      teamBName: "Swifts",
      teamBScore: 0
    )
    var state = AppFeature.State()
    state.selectedTab = .teams
    state.teamsPath.append(
      .teamDetail(TeamDetailFeature.State(teamID: UUID(1)))
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_100)
      $0.defaultDatabase = database
      $0.gameTimer = .live(system: .noop)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.teamGameRowTapped(game)) {
      $0.loadingGameID = game.id
      $0.loadingGameTab = .teams
    }
    await store.receive {
      guard case .resumeGameResponse(game.id, .success) = $0 else { return false }
      return true
    }

    expectNoDifference(store.state.loadingGameID, nil)
    expectNoDifference(store.state.loadingGameTab, nil)
    expectNoDifference(store.state.path.count, 0)
    expectNoDifference(store.state.teamsPath.count, 2)
    guard case let .scoring(scoring) = store.state.teamsPath[1] else {
      Issue.record("Expected scoring to resume in the Teams stack")
      return
    }
    expectNoDifference(scoring.gameID, game.id)

    let scoringID = store.state.teamsPath.ids[1]
    await store.send(
      .teamsPath(
        .element(
          id: scoringID,
          action: .scoring(.delegate(.gameFinished(game.id)))
        )
      )
    )

    expectNoDifference(store.state.path.count, 0)
    expectNoDifference(store.state.teamsPath.count, 2)
    guard case let .gameDetail(detail) = store.state.teamsPath[1] else {
      Issue.record("Expected scoring to finish in the Teams stack")
      return
    }
    expectNoDifference(detail.gameID, game.id)
  }

  @Test
  func gameDeepLinkSelectsTeamsForAnExistingTeamsScoringRoute() async {
    let scoring = Self.scoringState()
    let seedStore = Self.makeScoringStore(state: scoring)
    var state = AppFeature.State()
    state.teamsPath.append(.scoring(scoring))
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.defaultDatabase = seedStore.dependencies.defaultDatabase
      $0.gameTimer = .live(system: .noop)
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .deepLinkOpened(URL(string: "supershot://game/\(UUID(3).uuidString)")!)
    ) {
      $0.selectedTab = .teams
    }

    expectNoDifference(store.state.path.count, 0)
    expectNoDifference(store.state.teamsPath.count, 1)
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

  private static func setupState(
    leftName: String,
    rightName: String
  ) -> NewGameFeature.State {
    var state = NewGameFeature.State()
    state.leftTeam.mode = .locked
    state.leftTeam.selection = .new(
      TeamSlotFeature.TeamDraft(
        teamColorHex: TeamColorPalette.blue,
        name: leftName
      )
    )
    state.rightTeam.mode = .locked
    state.rightTeam.selection = .new(
      TeamSlotFeature.TeamDraft(
        teamColorHex: TeamColorPalette.red,
        name: rightName
      )
    )
    return state
  }
}

private nonisolated enum TimerSystemEvent: Equatable, Sendable {
  case activity(Date?)
  case alarm(Date?, requestsAuthorization: Bool)
  case cancelAlarm
  case endActivity
}

private nonisolated struct ZeroRandomNumberGenerator: RandomNumberGenerator, Sendable {
  mutating func next() -> UInt64 { 0 }
}

private nonisolated enum AlarmAuthorizationTestError: Error {
  case failed
}
