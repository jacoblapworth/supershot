import ComposableArchitecture
import CustomDump
import Dependencies
import Foundation
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct NewGameFeatureTests {
    @Test
    func setupAllowsMatchingTeamNames() {
      var state = Self.setupState(leftName: "Ravens", rightName: "Ravens")
      state.firstCentrePass = .teamA

      expectNoDifference(state.canStartGame, true)
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
        try! clearDatabase($0.defaultDatabase)
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
        try! clearDatabase($0.defaultDatabase)
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
      expectNoDifference(values.0?.colorHex, "#34C759")
      expectNoDifference(values.1?.name, "Ravens")
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
}

private nonisolated struct ZeroRandomNumberGenerator: RandomNumberGenerator, Sendable {
  mutating func next() -> UInt64 { 0 }
}
