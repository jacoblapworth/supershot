@testable import AlarmClient
@testable import AppSettings
import AppUI
import ComposableArchitecture
import CustomDump
@testable import Database
import Dependencies
import Foundation
@testable import GameAnalysis
@testable import GameCore
@testable import GameServices
@testable import LocationClient
@testable import NewGameFeature
@testable import PermissionsFeature
@testable import PreviewSupport
@testable import ScoringFeature
@testable import SharedModels
@testable import SoundEffectsClient
import SQLiteData
@testable import SubscriptionClient
import SwiftUI
@testable import TeamEditingFeature
import Testing
import TestSupport
@testable import UI
@testable import WidgetSupport

extension SupershotTestSuite {
  @MainActor
  struct NewGameFeatureTests {
    @Test
    func schedulingToggleInitializesAndClearsScheduledTime() async {
      let now = Date(timeIntervalSince1970: 1234)
      let store = TestStore(initialState: NewGameFeature.State()) {
        NewGameFeature()
      } withDependencies: {
        $0.date.now = now
      }

      #expect(!store.state.scheduled)
      await store.send(.binding(.set(\.scheduled, true))) {
        $0.scheduledAt = now
      }
      #expect(store.state.scheduled)

      let selectedTime = now.addingTimeInterval(3600)
      await store.send(.binding(.set(\.scheduledAt, selectedTime))) {
        $0.scheduledAt = selectedTime
      }
      await store.send(.binding(.set(\.scheduled, true)))
      await store.send(.binding(.set(\.scheduled, false))) {
        $0.scheduledAt = nil
      }
      #expect(!store.state.scheduled)
    }

    @Test
    func newGamesDefaultToEightMinuteQuartersAndOneMinuteBreaks() {
      let state = NewGameFeature.State()

      #expect(state.timing.breakStartPolicy == .automatic)
      #expect(state.firstCentrePass == .teamA)
      #expect(state.periodDuration.totalSeconds == 8 * 60)
      #expect(state.firstBreakDuration.totalSeconds == 60)
      #expect(state.halfTimeDuration.totalSeconds == 60)
      #expect(state.secondBreakDuration.totalSeconds == 60)
    }

    @Test
    func newGamesUseSavedDefaultTimes() {
      @Dependency(\.defaultAppStorage) var defaults
      defaults.set("manual", forKey: "defaultBreakStartPolicy")
      defaults.set(12 * 60, forKey: "defaultPeriodDurationSeconds")
      defaults.set(2 * 60, forKey: "defaultBreakDurationSeconds")

      let state = NewGameFeature.State()

      #expect(state.timing.breakStartPolicy == .manual)
      defaults.set("automatic", forKey: "defaultBreakStartPolicy")
      #expect(state.timing.breakStartPolicy == .manual)
      #expect(NewGameFeature.State().timing.breakStartPolicy == .automatic)

      expectNoDifference(state.periodDuration.totalSeconds, 12 * 60)
      expectNoDifference(state.firstBreakDuration.totalSeconds, 2 * 60)
      expectNoDifference(state.halfTimeDuration.totalSeconds, 2 * 60)
      expectNoDifference(state.secondBreakDuration.totalSeconds, 2 * 60)
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
      let ravens = Team(id: UUID(1), name: "Ravens", colorHex: ColorPalette.blue.hex())
      var state = NewGameFeature.State()
      state.rightTeam.team = ravens
      let store = TestStore(initialState: state) {
        NewGameFeature()
      }

      await store.send(.selectTeamButtonTapped(.teamA)) {
        $0.destination = .teamPicker(
          NewGameTeamPicker.State(
            picker: TeamPickerFeature.State(excluding: [ravens.id]),
            side: .teamA
          )
        )
      }
    }

    @Test(arguments: [NewGameFeature.TeamSide.teamA, .teamB])
    func pickingTeamReturnsToSetupWithTeamAndBibColor(side: NewGameFeature.TeamSide) async {
      let foxes = Team(id: UUID(2), name: "Foxes", colorHex: "#34C759")
      var state = NewGameFeature.State()
      state.destination = .teamPicker(
        NewGameTeamPicker.State(
          picker: TeamPickerFeature.State(),
          side: side
        )
      )
      let store = TestStore(initialState: state) {
        NewGameFeature()
      }

      await store.send(
        .destination(.presented(.teamPicker(.picker(.delegate(.teamSelected(foxes))))))
      ) {
        if side == .teamA {
          $0.leftTeam.bibColor = foxes.color
          $0.leftTeam.team = foxes
        } else {
          $0.rightTeam.bibColor = foxes.color
          $0.rightTeam.team = foxes
        }
        $0.destination = nil
      }
    }

    @Test(arguments: [NewGameFeature.TeamSide.teamA, .teamB])
    func tappingSelectedTeamOpensColourEditor(side: NewGameFeature.TeamSide) async {
      let foxes = Team(id: UUID(2), name: "Foxes", colorHex: "#34C759")
      let ravens = Team(id: UUID(1), name: "Ravens", colorHex: "#007AFF")
      var state = NewGameFeature.State()
      state.leftTeam.team = side == .teamA ? foxes : ravens
      state.rightTeam.team = side == .teamB ? foxes : ravens
      let store = TestStore(initialState: state) {
        NewGameFeature()
      }

      await store.send(.selectTeamButtonTapped(side)) {
        $0.destination = .teamConfiguration(
          NewGameTeamConfiguration.State(
            configuration: SetupTeamFeature.State(team: foxes, excluding: [ravens.id]),
            side: side
          )
        )
      }

      var updatedFoxes = foxes
      updatedFoxes.colorHex = "#FF9500"
      await store.send(
        .destination(.presented(.teamConfiguration(.configuration(.delegate(.teamUpdated(updatedFoxes))))))
      ) {
        if side == .teamA {
          $0.leftTeam.team = updatedFoxes
          $0.leftTeam.bibColor = updatedFoxes.color
        } else {
          $0.rightTeam.team = updatedFoxes
          $0.rightTeam.bibColor = updatedFoxes.color
        }
      }
      await store.send(.destination(.presented(.teamConfiguration(.configuration(.delegate(.done)))))) {
        $0.destination = nil
      }
    }

    @Test
    func editingTimingUsesTheSinglePresentationDestination() async {
      var state = NewGameFeature.State()
      state.destination = .teamPicker(
        NewGameTeamPicker.State(
          picker: TeamPickerFeature.State(),
          side: .teamA
        )
      )
      let store = TestStore(initialState: state) {
        NewGameFeature()
      }

      await store.send(.editTimingButtonTapped) {
        $0.destination = .timingEditor(SetupTimingFeature.State(timing: $0.timing))
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
        $0.locationRequestID = 1
      }
      await store.receive {
        guard case let .locationResponse(_, .success(receivedLocation)) = $0 else {
          return false
        }
        return receivedLocation == location
      } assert: {
        $0.location = .loaded
        $0.currentLocation = location
        $0.selectedLocation = location
        $0.nearbyPlacesStatus = .loading
        $0.locationRequestID = 2
      }
      await store.receive(\.nearbyPlacesResponse) { $0.nearbyPlacesStatus = .loaded }
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
        $0.locationRequestID = 1
      }
      await store.receive {
        guard case .locationResponse(_, .failure) = $0 else { return false }
        return true
      } assert: {
        $0.location = .failed
      }
      #expect(!store.state.isSaving)
    }

    @Test(arguments: [0, 60], [BreakStartPolicy.automatic, .manual])
    func preparingScoringUsesPersistedTeamsAndGameSpecificBibColors(breakSeconds: Int, policy: BreakStartPolicy) async throws {
      let ravens = Team(id: UUID(1), name: "Ravens", colorHex: ColorPalette.blue.hex())
      let swifts = Team(id: UUID(2), name: "Swifts", colorHex: ColorPalette.red.hex())
      var state = NewGameFeature.State()
      state.timing.breakStartPolicy = policy
      state.firstCentrePass = .teamB
      state.firstBreakDuration = .init(totalSeconds: breakSeconds)
      state.halfTimeDuration = .init(totalSeconds: breakSeconds)
      state.secondBreakDuration = .init(totalSeconds: breakSeconds)
      state.location = .loaded
      state.currentLocation = GameLocation(latitude: 51.55, longitude: -0.28)
      state.selectedLocation = GameLocation(
        latitude: 51.556,
        longitude: -0.2796,
        pointOfInterestName: "Wembley Arena"
      )
      state.leftTeam = .init(bibColor: Color(hex: "#AF52DE"))
      state.leftTeam.team = ravens
      state.rightTeam = .init(bibColor: Color(hex: "#FF2D55"))
      state.rightTeam.team = swifts
      let startedAt = Date(timeIntervalSince1970: 1000)
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

      await store.send(.prepareScoringButtonTapped) {
        $0.inFlightDraft = $0.draft
        $0.isSaving = true
      }
      await store.receive {
        guard case .prepareScoringResponse(.success) = $0 else { return false }
        return true
      } assert: {
        $0.inFlightDraft = nil
        $0.hasEnteredScoring = true
        $0.isSaving = false
      }
      await store.receive {
        guard case .delegate(.scoringPrepared) = $0 else { return false }
        return true
      }

      let (game, periods) = try await store.dependencies.defaultDatabase.read { db in
        try (
          Game.fetchOne(db),
          GamePeriod.order { $0.position }.fetchAll(db)
        )
      }
      #expect(game?.breakStartPolicy == policy)
      expectNoDifference(game?.teamAID, ravens.id)
      expectNoDifference(game?.teamBID, swifts.id)
      expectNoDifference(game?.teamABibColorHex, "#AF52DE")
      expectNoDifference(game?.teamBBibColorHex, "#FF2D55")
      expectNoDifference(periods.map(\.durationSeconds), [480, 480, 480, 480])
      let storedBreak: Int? = breakSeconds == 0 ? nil : breakSeconds
      expectNoDifference(periods.map(\.breakAfterDurationSeconds), [storedBreak, storedBreak, storedBreak, nil])
      let timeline = try #require(GameTimeline(periods: periods))
      #expect(timeline.phases.count == (breakSeconds == 0 ? 4 : 7))
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
