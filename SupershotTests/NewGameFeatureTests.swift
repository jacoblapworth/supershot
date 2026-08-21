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
    func newGamesDefaultToEightMinuteQuartersAndOneMinuteBreaks() {
      let state = NewGameFeature.State()

      #expect(state.periodDuration.totalSeconds == 8 * 60)
      #expect(state.firstBreakDuration.totalSeconds == 60)
      #expect(state.halfTimeDuration.totalSeconds == 60)
      #expect(state.secondBreakDuration.totalSeconds == 60)
    }

    @Test
    func pickerFiltersExcludedTeams() async {
      let ravens = Team(id: UUID(1), name: "Ravens")
      let swifts = Team(id: UUID(2), name: "Swifts")
      let store = TestStore(
        initialState: TeamPickerFeature.State(excluding: [ravens.id])
      ) {
        TeamPickerFeature()
      }

      await store.send(.teamsResponse(.success([ravens, swifts]))) {
        $0.availableTeams = [ravens, swifts]
      }
      expectNoDifference(store.state.filteredTeams, [swifts])
    }

    @Test
    func newlyCreatedTeamIsSelectedImmediately() async {
      let falcons = Team(id: UUID(3), name: "Falcons", colorHex: "#34C759")
      var state = TeamPickerFeature.State()
      state.editor = TeamEditorFeature.State()
      let store = TestStore(initialState: state) {
        TeamPickerFeature()
      }

      await store.send(.editor(.presented(.delegate(.saved(falcons))))) {
        $0.editor = nil
      }
      await store.receive {
        guard case .delegate(.teamSelected(falcons)) = $0 else { return false }
        return true
      }
    }

    @Test
    func selectingTeamExcludesTheOpponent() async {
      let ravens = Team(id: UUID(1), name: "Ravens", colorHex: TeamColorPalette.blue)
      var state = NewGameFeature.State()
      state.rightTeam.team = ravens
      let store = TestStore(initialState: state) {
        NewGameFeature()
      }

      await store.send(.selectTeamButtonTapped(.teamA)) {
        $0.firstCentrePass = nil
        $0.picker = TeamPickerFeature.State(excluding: [ravens.id])
        $0.pickingTeamSide = .teamA
      }
    }

    @Test
    func pickedTeamSetsMatchTeamAndBibColor() async {
      let foxes = Team(id: UUID(2), name: "Foxes", colorHex: "#34C759")
      var state = NewGameFeature.State()
      state.picker = TeamPickerFeature.State()
      state.pickingTeamSide = .teamA
      let store = TestStore(initialState: state) {
        NewGameFeature()
      }

      await store.send(.picker(.presented(.delegate(.teamSelected(foxes))))) {
        $0.leftTeam.bibColorHex = "#34C759"
        $0.leftTeam.team = foxes
        $0.picker = nil
        $0.pickingTeamSide = nil
      }
    }

    @Test
    func setupLoadsAuthorizedCurrentLocation() async {
      let location = GameLocation(
        latitude: 51.556,
        longitude: -0.2796,
        pointOfInterestName: "Wembley Arena"
      )
      let store = TestStore(initialState: NewGameFeature.State()) {
        NewGameFeature()
      } withDependencies: {
        $0.locationClient = LocationClient(
          authorizationStatus: { .authorized },
          currentLocation: { location },
          requestAuthorization: { .authorized }
        )
      }

      await store.send(.task) {
        $0.location = .loading
      }
      await store.receive {
        guard case let .locationResponse(.success(receivedLocation)) = $0 else {
          return false
        }
        return receivedLocation == location
      } assert: {
        $0.location = .loaded(location)
      }
    }

    @Test
    func setupLocationFailureDoesNotPreventGameConfiguration() async {
      let store = TestStore(initialState: NewGameFeature.State()) {
        NewGameFeature()
      } withDependencies: {
        $0.locationClient = LocationClient(
          authorizationStatus: { .authorized },
          currentLocation: { throw LocationClientError.locationUnavailable },
          requestAuthorization: { .authorized }
        )
      }

      await store.send(.task) {
        $0.location = .loading
      }
      await store.receive {
        guard case .locationResponse(.failure) = $0 else { return false }
        return true
      } assert: {
        $0.location = .unavailable(canRetry: true)
      }
      #expect(!store.state.isSaving)
    }

    @Test
    func startGameUsesPersistedTeamsAndGameSpecificBibColors() async throws {
      let ravens = Team(id: UUID(1), name: "Ravens", colorHex: TeamColorPalette.blue)
      let swifts = Team(id: UUID(2), name: "Swifts", colorHex: TeamColorPalette.red)
      var state = NewGameFeature.State()
      state.firstCentrePass = .teamB
      state.location = .loaded(
        GameLocation(
          latitude: 51.556,
          longitude: -0.2796,
          pointOfInterestName: "Wembley Arena"
        )
      )
      state.leftTeam = .init(bibColorHex: "#AF52DE")
      state.leftTeam.team = ravens
      state.rightTeam = .init(bibColorHex: "#FF2D55")
      state.rightTeam.team = swifts
      let startedAt = Date(timeIntervalSince1970: 1_000)
      let store = TestStore(initialState: state) {
        NewGameFeature()
      } withDependencies: {
        $0.date.now = startedAt
        $0.uuid = .incrementing
        try! $0.bootstrapDatabase()
        try! clearDatabase($0.defaultDatabase)
        try! $0.defaultDatabase.write { db in
          try Team.insert { ravens; swifts }.execute(db)
        }
      }

      await store.send(.startGameButtonTapped) {
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

      let (game, periods) = try await store.dependencies.defaultDatabase.read { db in
        (
          try Game.fetchOne(db),
          try GamePeriod.order { $0.position }.fetchAll(db)
        )
      }
      expectNoDifference(game?.teamAID, ravens.id)
      expectNoDifference(game?.teamBID, swifts.id)
      expectNoDifference(game?.teamABibColorHex, "#AF52DE")
      expectNoDifference(game?.teamBBibColorHex, "#FF2D55")
      expectNoDifference(periods.map(\.durationSeconds), [480, 480, 480, 480])
      expectNoDifference(periods.map(\.breakAfterDurationSeconds), [60, 60, 60, nil])
      expectNoDifference(
        game?.location,
        GameLocation(
          latitude: 51.556,
          longitude: -0.2796,
          pointOfInterestName: "Wembley Arena"
        )
      )
    }
  }
}
