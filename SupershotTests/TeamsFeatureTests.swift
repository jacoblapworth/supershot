import SwiftUI
import ComposableArchitecture
import CustomDump
import DependenciesTestSupport
import Foundation
import GRDB
import OrderedCollections
import SQLiteData
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite(.dependencies {
    $0.uuid = .incrementing
  }) struct TeamsFeatureTests {
    
    @Test
    func newGameFromTeamDetailPreselectsTeam() async {
      let team = Team(id: UUID(1), name: "Ravens", colorHex: ColorPalette.blue.hex())
      let store = TestStore(initialState: {
        var state = TeamsFeature.State()
        state.path.append(.teamDetail(TeamDetailFeature.State(teamID: team.id)))
        return state
      }()) {
        TeamsFeature()
      }
      store.exhaustivity = .off(showSkippedAssertions: false)
      let detailID = store.state.path.ids[0]
      
      await store.send(
        .path(.element(id: detailID, action: .teamDetail(.newGameButtonTapped(team))))
      )
      await store.receive {
        guard case .path(.element(id: detailID, action: .teamDetail(.delegate(.newGameButtonTapped(team))))) = $0 else {
          return false
        }
        return true
      }
      var setup = NewGameFeature.State()
      setup.leftTeam.team = team
      setup.leftTeam.bibColor = team.color
      expectNoDifference(
        Array(store.state.path),
        [.teamDetail(TeamDetailFeature.State(teamID: team.id)), .setup(setup)]
      )
      
      let setupID = store.state.path.ids[1]
      let scoring = ScoringFeature.State(
        centrePassTeamID: team.id,
        gameID: UUID(3),
        periods: testGamePeriods(gameID: UUID(3)),
        startedAt: Date(timeIntervalSince1970: 500),
        teamA: ScoringFeature.Team(id: team.id, bibColor: team.color, name: team.name),
        teamB: ScoringFeature.Team(id: UUID(2), bibColor: ColorPalette.red, name: "Swifts")
      )
      await store.send(
        .path(.element(id: setupID, action: .setup(.delegate(.gameStarted(scoring)))))
      )
      expectNoDifference(
        Array(store.state.path),
        [.teamDetail(TeamDetailFeature.State(teamID: team.id)), .scoring(scoring)]
      )
    }
    
    @Test
    func searchMatchesNamesAndClearingRestoresTeams() async {
      let teams = [
        TeamListItem(color: ColorPalette.blue, gameCount: 2, id: UUID(1), name: "Ravens"),
        TeamListItem(color: ColorPalette.red, gameCount: 0, id: UUID(2), name: "Café Swifts"),
      ]
      let store = TestStore(initialState: TeamsFeature.State()) {
        TeamsFeature()
      }
      
      await store.send(.binding(.set(\.searchText, "  CAFE \n"))) {
        $0.searchText = "  CAFE \n"
      }
      expectNoDifference(store.state.filteredTeams(in: teams), [teams[1]])
      
      await store.send(.binding(.set(\.searchText, "aven"))) {
        $0.searchText = "aven"
      }
      expectNoDifference(store.state.filteredTeams(in: teams), [teams[0]])
      
      await store.send(.binding(.set(\.searchText, "missing"))) {
        $0.searchText = "missing"
      }
      expectNoDifference(store.state.filteredTeams(in: teams), [])
      
      await store.send(.binding(.set(\.searchText, " \n"))) {
        $0.searchText = " \n"
      }
      expectNoDifference(store.state.filteredTeams(in: teams), teams)
    }
    
    @Test
    func completedTeamGameOpensDetail() async {
      let game = GameListItem(
        endedAt: Date(timeIntervalSince1970: 2_000),
        id: UUID(3),
        startedAt: Date(timeIntervalSince1970: 1_000),
        teamAName: "Ravens",
        teamAScore: 12,
        teamBName: "Swifts",
        teamBScore: 10
      )
      let store = TestStore(initialState: TeamsFeature.State()) {
        TeamsFeature()
      }
      
      await store.send(.teamGameRowTapped(game)) {
        $0.path.append(
          .gameDetail(GameDetailFeature.State(gameID: game.id))
        )
      }
    }
    
    @Test
    func teamSelectionAndCreationStayWithinTeamsTab() async {
      let team = TeamListItem(
        color: ColorPalette.blue,
        gameCount: 2,
        id: UUID(1),
        name: "Ravens"
      )
      let store = TestStore(initialState: TeamsFeature.State()) {
        TeamsFeature()
      }
      
      await store.send(.teamRowTapped(team)) {
        $0.path.append(
          .teamDetail(TeamDetailFeature.State(teamID: team.id))
        )
      }
      await store.send(.newTeamButtonTapped) {
        $0.destination = .teamEditor(TeamsEditorFeature.State())
      }
    }
    
    @Test
    func unfinishedTeamGameResumesAndFinishesInTeamsStack() async {
      let game = GameListItem(
        endedAt: nil,
        id: UUID(3),
        startedAt: Date(timeIntervalSince1970: 500),
        teamAName: "Ravens",
        teamAScore: 0,
        teamBName: "Swifts",
        teamBScore: 0
      )
      var state = TeamsFeature.State()
      state.path.append(
        .teamDetail(TeamDetailFeature.State(teamID: UUID(1)))
      )
      let store = Self.makeStore(state: state)
      store.exhaustivity = .off(showSkippedAssertions: false)
      
      await store.send(.teamGameRowTapped(game)) {
        $0.pendingGameResume = TeamsFeature.PendingGameResume(
          gameID: game.id,
          requestID: UUID(0)
        )
      }
      await store.receive {
        guard case let .resumeGameResponse(request, .success) = $0 else {
          return false
        }
        return request.gameID == game.id
      }
      
      expectNoDifference(store.state.pendingGameResume, nil)
      expectNoDifference(store.state.path.count, 2)
      guard case let .scoring(scoring) = store.state.path[1] else {
        Issue.record("Expected scoring to resume in the Teams stack")
        return
      }
      expectNoDifference(scoring.gameID, game.id)
      
      let scoringID = store.state.path.ids[1]
      await store.send(
        .path(
          .element(
            id: scoringID,
            action: .scoring(.delegate(.gameFinished(game.id)))
          )
        )
      )
      
      expectNoDifference(store.state.path.count, 2)
      guard case let .gameDetail(detail) = store.state.path[1] else {
        Issue.record("Expected scoring to finish in the Teams stack")
        return
      }
      expectNoDifference(detail.gameID, game.id)
    }
    
    @Test
    func staleResumeResponseIsIgnored() async {
      let currentRequest = TeamsFeature.PendingGameResume(
        gameID: UUID(3),
        requestID: UUID(2)
      )
      var state = TeamsFeature.State()
      state.pendingGameResume = currentRequest
      var editor = TeamsEditorFeature.State()
      editor.editor.name = "Draft team"
      editor.alert = .gameUnavailable
      state.destination = .teamEditor(editor)
      let store = TestStore(initialState: state) {
        TeamsFeature()
      }
      let staleRequest = TeamsFeature.PendingGameResume(
        gameID: UUID(3),
        requestID: UUID(1)
      )
      
      await store.send(
        .resumeGameResponse(
          staleRequest,
          .failure(TabFeatureTestError.unavailable)
        )
      )
    }

    @Test
    func resumeFailurePresentsRootAlertAndDismisses() async {
      var gameTimer = GameTimerClient.live
      gameTimer.reconcile = { _ in throw TabFeatureTestError.unavailable }
      let store = Self.makeStore(gameTimer: gameTimer)
      let request = TeamsFeature.PendingGameResume(gameID: UUID(3), requestID: UUID(0))

      await store.send(.gameDeepLinkOpened(request.gameID)) {
        $0.pendingGameResume = request
      }
      await store.receive(\.resumeGameResponse) {
        $0.pendingGameResume = nil
        $0.destination = .alert(.gameUnavailable)
      }
      await store.send(.destination(.presented(.alert(.dismissButtonTapped)))) {
        $0.destination = nil
      }
      await store.finish()
    }

    @Test(arguments: [false, true])
    func resumeFailureWhileEditingPreservesDraftAndStack(opensEditorDuringResume: Bool) async {
      let (responses, continuation) = AsyncStream<Void>.makeStream()
      var gameTimer = GameTimerClient.live
      gameTimer.reconcile = { _ in
        for await _ in responses { break }
        throw TabFeatureTestError.unavailable
      }
      var state = TeamsFeature.State()
      state.path.append(.teamDetail(TeamDetailFeature.State(teamID: UUID(1))))
      let store = Self.makeStore(state: state, gameTimer: gameTimer)
      let request = TeamsFeature.PendingGameResume(gameID: UUID(3), requestID: UUID(0))

      if opensEditorDuringResume {
        await store.send(.gameDeepLinkOpened(request.gameID)) {
          $0.pendingGameResume = request
        }
      }
      await store.send(.newTeamButtonTapped) {
        $0.destination = .teamEditor(TeamsEditorFeature.State())
      }
      await store.send(.destination(.presented(.teamEditor(.editor(.binding(.set(\.name, "Draft team"))))))) {
        Self.updateEditor(in: &$0) { $0.editor.name = "Draft team" }
      }
      if !opensEditorDuringResume {
        await store.send(.gameDeepLinkOpened(request.gameID)) {
          $0.pendingGameResume = request
        }
      }
      continuation.yield(())
      continuation.finish()
      await store.receive(\.resumeGameResponse) {
        $0.pendingGameResume = nil
        Self.updateEditor(in: &$0) { $0.alert = .gameUnavailable }
      }
      await store.send(.destination(.presented(.teamEditor(.alert(.presented(.dismissButtonTapped)))))) {
        Self.updateEditor(in: &$0) { $0.alert = nil }
      }
      expectNoDifference(store.state.destination?.teamEditor?.editor.name, "Draft team")
      expectNoDifference(Array(store.state.path), Array(state.path))
      await store.finish()
    }

    @Test(arguments: [false, true])
    func editorCancellationDismissesEntirePresentation(hasAlert: Bool) async {
      var editor = TeamsEditorFeature.State()
      editor.editor.name = "Unsaved team"
      editor.alert = hasAlert ? .gameUnavailable : nil
      var state = TeamsFeature.State()
      state.destination = .teamEditor(editor)
      let store = TestStore(initialState: state) { TeamsFeature() }

      await store.send(.destination(.presented(.teamEditor(.editor(.cancelButtonTapped)))))
      await store.receive(\.destination.teamEditor.editor.delegate) {
        $0.destination = nil
      }
      await store.finish()
    }

    @Test(arguments: [false, true])
    func sheetDismissalDiscardsEditorAndNestedAlert(hasAlert: Bool) async {
      var editor = TeamsEditorFeature.State()
      editor.alert = hasAlert ? .gameUnavailable : nil
      var state = TeamsFeature.State()
      state.destination = .teamEditor(editor)
      let store = TestStore(initialState: state) { TeamsFeature() }

      await store.send(.destination(.dismiss)) {
        $0.destination = nil
      }
      await store.finish()
    }

    @Test(arguments: [false, true])
    func editorSavePersistsAndDismisses(hasAlert: Bool) async throws {
      var state = TeamsFeature.State()
      var editor = TeamsEditorFeature.State()
      editor.alert = hasAlert ? .gameUnavailable : nil
      state.destination = .teamEditor(editor)
      let store = Self.makeStore(state: state)
      let database = store.dependencies.defaultDatabase
      await store.send(.destination(.presented(.teamEditor(.editor(.binding(.set(\.name, "New team"))))))) {
        Self.updateEditor(in: &$0) { $0.editor.name = "New team" }
      }
      await store.send(.destination(.presented(.teamEditor(.editor(.saveButtonTapped))))) {
        Self.updateEditor(in: &$0) { $0.editor.isSaving = true }
      }
      await store.receive(\.destination.teamEditor.editor.saveResponse) {
        Self.updateEditor(in: &$0) { $0.editor.isSaving = false }
      }
      await store.receive(\.destination.teamEditor.editor.delegate) {
        $0.destination = nil
      }
      let savedName = try await database.read { try Team.find(UUID(0)).fetchOne($0)?.name }
      expectNoDifference(savedName, "New team")
      await store.finish()
    }

    @Test
    func nestedAlertSystemDismissalPreservesEditor() async {
      var state = TeamsFeature.State()
      var editor = TeamsEditorFeature.State()
      editor.editor.name = "Draft team"
      editor.alert = .gameUnavailable
      state.destination = .teamEditor(editor)
      let store = TestStore(initialState: state) { TeamsFeature() }

      await store.send(.destination(.presented(.teamEditor(.alert(.dismiss))))) {
        Self.updateEditor(in: &$0) { $0.alert = nil }
      }
    }

    @Test
    func successfulDeepLinkKeepsEditorAndAppendsScoring() async {
      var state = TeamsFeature.State()
      var editor = TeamsEditorFeature.State()
      editor.editor.name = "Draft team"
      state.destination = .teamEditor(editor)
      state.path.append(.teamDetail(TeamDetailFeature.State(teamID: UUID(1))))
      let store = Self.makeStore(state: state)
      await store.send(.gameDeepLinkOpened(UUID(3))) {
        $0.pendingGameResume = TeamsFeature.PendingGameResume(gameID: UUID(3), requestID: UUID(0))
      }
      let snapshot = try! await store.dependencies.defaultDatabase.read {
        try GameSnapshot.fetch($0, gameID: UUID(3))
      }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.receive(\.resumeGameResponse)
      expectNoDifference(store.state.pendingGameResume, nil)
      expectNoDifference(
        Array(store.state.path),
        [.teamDetail(TeamDetailFeature.State(teamID: UUID(1))), .scoring(ScoringFeature.State(snapshot: snapshot))]
      )
      expectNoDifference(store.state.destination, state.destination)
      await store.finish()
    }

    @Test(arguments: [false, true])
    func deletionFailureKeepsEditorAndDoesNotEndPresentation(deletesTeam: Bool) async throws {
      let endedGameIDs = LockIsolated<[Game.ID]>([])
      var gameTimer = GameTimerClient.live
      gameTimer.endPresentation = { gameID in
        endedGameIDs.withValue { $0.append(gameID) }
      }
      var state = TeamsFeature.State()
      var editor = TeamsEditorFeature.State()
      editor.editor.name = "Draft team"
      editor.alert = .gameUnavailable
      state.destination = .teamEditor(editor)
      let store = Self.makeStore(state: state, gameTimer: gameTimer)
      let database = store.dependencies.defaultDatabase
      try await database.write { db in
        try db.execute(sql: """
          CREATE TRIGGER fail_game_delete BEFORE DELETE ON games
          BEGIN SELECT RAISE(ABORT, 'Test deletion failure'); END;
          """)
      }
      await withKnownIssue {
        await store.send(deletesTeam ? .deleteTeamButtonTapped(UUID(1)) : .deleteGameButtonTapped(UUID(3)))
        await store.finish()
      }
      try await database.write { db in
        try db.execute(sql: "DROP TRIGGER fail_game_delete")
      }
      expectNoDifference(store.state.destination, state.destination)
      expectNoDifference(endedGameIDs.value, [])
      let teamName = try await database.read { try Team.find(UUID(1)).fetchOne($0)?.name }
      expectNoDifference(teamName, "Ravens")
      #expect(try await database.read { try Game.find(UUID(3)).fetchOne($0) } != nil)
    }

    @Test
    func failureAfterSheetDismissalPresentsRootAlert() async {
      let request = TeamsFeature.PendingGameResume(gameID: UUID(3), requestID: UUID(0))
      var state = TeamsFeature.State()
      state.destination = .teamEditor(TeamsEditorFeature.State())
      state.pendingGameResume = request
      let store = TestStore(initialState: state) { TeamsFeature() }

      await store.send(.destination(.dismiss)) {
        $0.destination = nil
      }
      await store.send(.resumeGameResponse(request, .failure(TabFeatureTestError.unavailable))) {
        $0.pendingGameResume = nil
        $0.destination = .alert(.gameUnavailable)
      }
      await store.send(.destination(.dismiss)) {
        $0.destination = nil
      }
    }

    @Test(arguments: [false, true])
    func newResumeClearsAlertFromItsOwner(hasEditor: Bool) async {
      let (responses, continuation) = AsyncStream<Void>.makeStream()
      var gameTimer = GameTimerClient.live
      gameTimer.reconcile = { _ in
        for await _ in responses { break }
        throw TabFeatureTestError.unavailable
      }
      var state = TeamsFeature.State()
      if hasEditor {
        var editor = TeamsEditorFeature.State()
        editor.editor.name = "Draft team"
        editor.alert = .gameUnavailable
        state.destination = .teamEditor(editor)
      } else {
        state.destination = .alert(.gameUnavailable)
      }
      let store = Self.makeStore(state: state, gameTimer: gameTimer)
      await store.send(.gameDeepLinkOpened(UUID(3))) {
        $0.pendingGameResume = TeamsFeature.PendingGameResume(gameID: UUID(3), requestID: UUID(0))
        if hasEditor {
          Self.updateEditor(in: &$0) { $0.alert = nil }
        } else {
          $0.destination = nil
        }
      }
      continuation.yield(())
      continuation.finish()
      await store.receive(\.resumeGameResponse) {
        $0.pendingGameResume = nil
        if hasEditor {
          Self.updateEditor(in: &$0) { $0.alert = .gameUnavailable }
        } else {
          $0.destination = .alert(.gameUnavailable)
        }
      }
      await store.finish()
    }
    
    @Test
    func deletingTeamCascadesGamesAndGoalsAndEndsPresentations() async throws {
      let endedGameIDs = LockIsolated<[Game.ID]>([])
      var gameTimer = GameTimerClient.live
      gameTimer.endPresentation = { gameID in
        endedGameIDs.withValue { $0.append(gameID) }
      }
      let store = Self.makeStore(gameTimer: gameTimer)
      let database = store.dependencies.defaultDatabase
      
      await store.send(.deleteTeamButtonTapped(UUID(1)))
      await store.finish()
      
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
      expectNoDifference(endedGameIDs.value, [UUID(3)])
    }
    
    @Test
    func promotionDelegatesToApp() async {
      let store = TestStore(initialState: TeamsFeature.State()) {
        TeamsFeature()
      }
      
      await store.send(.proPromotionTapped)
      await store.receive {
        guard case .delegate(.proPromotionTapped) = $0 else { return false }
        return true
      }
    }
    
    private static func updateEditor(
      in state: inout TeamsFeature.State,
      _ update: (inout TeamsEditorFeature.State) -> Void
    ) {
      guard case var .teamEditor(editor) = state.destination else {
        Issue.record("Expected a team editor destination")
        return
      }
      update(&editor)
      state.destination = .teamEditor(editor)
    }

    private static func makeStore(
      state: TeamsFeature.State? = nil,
      gameTimer: GameTimerClient = .live
    ) -> TestStoreOf<TeamsFeature> {
      TestStore(initialState: state ?? TeamsFeature.State()) {
        TeamsFeature()
      } withDependencies: {
        $0.date.now = Date(timeIntervalSince1970: 1_100)
        $0.uuid = .incrementing
        try! clearDatabase($0.defaultDatabase)
        try! $0.defaultDatabase.write { db in
          try Self.seedGameAndGoal(db)
        }
        $0.gameTimer = gameTimer
      }
    }
    
    private nonisolated static func seedGameAndGoal(_ db: Database) throws {
      try Team.insert {
        Team(id: UUID(1), name: "Ravens")
        Team(id: UUID(2), name: "Swifts")
      }
      .execute(db)
      try Game.insert {
        Game(
          id: UUID(3),
          startedAt: Date(timeIntervalSince1970: 500),
          endedAt: nil,
          teamAID: UUID(1),
          teamBID: UUID(2),
          centrePassTeamID: UUID(1),
          isAwaitingCentrePassConfirmation: false,
          currentPhaseIndex: 0,
          elapsedSeconds: 0,
          timerEndsAt: nil
        )
      }
      .execute(db)
      try GamePeriod.insert { testGamePeriods(gameID: UUID(3)) }.execute(db)
      try Goal.insert {
        Goal(
          id: UUID(4),
          gameID: UUID(3),
          gamePeriodID: testGamePeriodID(gameID: UUID(3), position: 0),
          teamID: UUID(1),
          elapsedSeconds: 10,
          points: 1,
          createdAt: Date(timeIntervalSince1970: 1_000)
        )
      }
      .execute(db)
    }
  }
}
