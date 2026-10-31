import ComposableArchitecture
import CustomDump
import Dependencies
import Foundation
@testable import LocationClient
@testable import NewGameFeature
@testable import SharedModels
import Testing
import TestSupport

extension SupershotTestSuite {
  @MainActor
  struct SetupLocationTests {
    private let coordinates = GameLocation(latitude: 51.556, longitude: -0.2796)
    private let arena = NearbyPlace(
      location: GameLocation(latitude: 51.557, longitude: -0.279, pointOfInterestName: "Arena"),
      distance: 120
    )
    private let park = NearbyPlace(
      location: GameLocation(latitude: 51.558, longitude: -0.278, pointOfInterestName: "Park"),
      distance: 250
    )

    @Test
    func coordinatesAreAvailableBeforeNearbyPlacesFinish() async {
      let clock = TestClock()
      let places = [arena, park]
      let store = TestStore(initialState: NewGameFeature.State()) { NewGameFeature() } withDependencies: {
        $0.locationClient = .preview
        $0.locationClient.nearbyPlaces = { _ in
          try await clock.sleep(for: .seconds(1))
          return places
        }
      }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.task)
      await store.receive(\.locationResponse)
      expectNoDifference(store.state.currentLocation, coordinates)
      expectNoDifference(store.state.gameLocation, coordinates)
      #expect(store.state.nearbyPlacesStatus == .loading)
      await clock.advance(by: .seconds(1))
      await store.receive(\.nearbyPlacesResponse)
      expectNoDifference(store.state.gameLocation, arena.location)
      expectNoDifference(store.state.currentLocation, coordinates)
      expectNoDifference(store.state.nearbyPlaces, places)
      await store.finish()
    }

    @Test(arguments: [true, false])
    func explicitSelectionSurvivesLateNearbyResults(useCurrentLocation: Bool) async {
      let clock = TestClock()
      let places = [arena]
      var state = NewGameFeature.State()
      state.currentLocation = coordinates
      state.selectedLocation = coordinates
      state.location = .loaded
      state.nearbyPlaces = [park]
      let store = TestStore(initialState: state) { NewGameFeature() } withDependencies: {
        $0.locationClient = .preview
        $0.locationClient.nearbyPlaces = { _ in
          try await clock.sleep(for: .seconds(1))
          return places
        }
      }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.locationButtonTapped)
      await store.receive(\.locationResponse)
      await store.send(.changeLocationButtonTapped)
      #expect(store.state.destination != nil)
      if useCurrentLocation {
        await store.send(.destination(.presented(.locationPicker(.currentLocationTapped))))
      } else {
        await store.send(.destination(.presented(.locationPicker(.placeTapped(park.id)))))
      }
      let selected = useCurrentLocation ? coordinates : park.location
      expectNoDifference(store.state.gameLocation, selected)
      #expect(store.state.destination == nil)
      await clock.advance(by: .seconds(1))
      await store.receive(\.nearbyPlacesResponse)
      expectNoDifference(store.state.gameLocation, selected)
      expectNoDifference(store.state.currentLocation, coordinates)
      #expect(store.state.preservesLocationSelection)
      await store.finish()
    }

    @Test
    func failedPlaceSearchKeepsCoordinatesAndCanRetryInSheet() async {
      let store = TestStore(initialState: NewGameFeature.State()) { NewGameFeature() } withDependencies: {
        $0.locationClient = .preview
        $0.locationClient.nearbyPlaces = { _ in throw LocationClientError.locationUnavailable }
      }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.task)
      await store.receive(\.locationResponse)
      await store.receive(\.nearbyPlacesResponse)
      expectNoDifference(store.state.gameLocation, coordinates)
      #expect(store.state.nearbyPlacesStatus == .failed)
      // Opening Change retries a failed lookup, and its state stays in sync with the sheet.
      await store.send(.changeLocationButtonTapped)
      await store.receive(\.nearbyPlacesResponse)
      guard case let .locationPicker(picker) = store.state.destination else {
        Issue.record("Expected location picker")
        return
      }
      #expect(picker.status == .failed)
      expectNoDifference(picker.currentLocation, coordinates)
      let places = [arena]
      store.dependencies.locationClient.nearbyPlaces = { _ in places }
      await store.send(.destination(.presented(.locationPicker(.retryButtonTapped))))
      await store.receive(\.nearbyPlacesResponse)
      expectNoDifference(store.state.gameLocation, arena.location)
      guard case let .locationPicker(updated) = store.state.destination else {
        Issue.record("Expected location picker to remain open")
        return
      }
      #expect(updated.status == .loaded)
      expectNoDifference(updated.places, places)
      await store.finish()
    }

    @Test
    func emptySearchKeepsUnnamedLocation() async {
      let store = TestStore(initialState: NewGameFeature.State()) { NewGameFeature() } withDependencies: {
        $0.locationClient = .preview
      }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.task)
      await store.receive(\.locationResponse)
      await store.receive(\.nearbyPlacesResponse)
      #expect(store.state.nearbyPlacesStatus == .loaded)
      #expect(store.state.nearbyPlaces.isEmpty)
      expectNoDifference(store.state.gameLocation, coordinates)
      await store.send(.changeLocationButtonTapped)
      await store.send(.destination(.presented(.locationPicker(.closeButtonTapped))))
      expectNoDifference(store.state.gameLocation, coordinates)
      #expect(store.state.destination == nil)
      await store.finish()
    }

    @Test(arguments: [true, false])
    func preservedSelectionSurvivesRefreshAndFailure(fails: Bool) async {
      var state = NewGameFeature.State()
      state.location = .loaded
      state.currentLocation = coordinates
      state.selectedLocation = park.location
      state.preservesLocationSelection = true
      let places = [arena]
      let store = TestStore(initialState: state) { NewGameFeature() } withDependencies: {
        $0.locationClient = .preview
        $0.locationClient.currentLocation = {
          if fails {
            throw LocationClientError.locationUnavailable
          }
          return LocationClient.previewCoordinates
        }
        $0.locationClient.nearbyPlaces = { _ in places }
      }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.locationButtonTapped)
      expectNoDifference(store.state.gameLocation, park.location)
      expectNoDifference(store.state.currentLocation, coordinates)
      await store.receive(\.locationResponse)
      if !fails {
        await store.receive(\.nearbyPlacesResponse)
      }
      expectNoDifference(store.state.gameLocation, park.location)
      expectNoDifference(store.state.currentLocation, coordinates)
      await store.finish()
    }

    @Test
    func refreshCancelsAnOlderPlaceSearch() async {
      let clock = TestClock()
      let cancelled = LockIsolated(false)
      let store = TestStore(initialState: NewGameFeature.State()) { NewGameFeature() } withDependencies: {
        $0.locationClient = .preview
        $0.locationClient.nearbyPlaces = { _ in
          do {
            try await clock.sleep(for: .seconds(60))
            Issue.record("Superseded search should have been cancelled")
            return []
          } catch {
            cancelled.setValue(true)
            throw error
          }
        }
      }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.task)
      await store.receive(\.locationResponse)
      store.dependencies.locationClient.nearbyPlaces = { _ in [] }
      await store.send(.locationButtonTapped)
      await store.receive(\.locationResponse)
      await store.receive(\.nearbyPlacesResponse)
      await store.finish()
      #expect(cancelled.value)
      expectNoDifference(store.state.gameLocation, coordinates)
      #expect(store.state.nearbyPlacesStatus == .loaded)
    }

    @Test
    func staleLocationAndPlaceResponsesCannotReplaceCurrentSelection() async {
      var state = NewGameFeature.State()
      state.location = .loaded
      state.currentLocation = coordinates
      state.selectedLocation = park.location
      state.locationRequestID = 5
      let store = TestStore(initialState: state) { NewGameFeature() }
      await store.send(.locationResponse(4, .success(arena.location)))
      await store.send(.locationResponse(4, .failure(LocationClientError.locationUnavailable)))
      await store.send(.nearbyPlacesResponse(4, .success([arena])))
      await store.send(.nearbyPlacesResponse(4, .failure(LocationClientError.locationUnavailable)))
    }
  }
}
