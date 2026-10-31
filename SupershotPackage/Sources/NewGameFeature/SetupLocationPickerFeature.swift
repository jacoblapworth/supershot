import ComposableArchitecture
import LocationClient
import SharedModels

package nonisolated enum SetupLocationStatus: Equatable, Sendable {
  case idle
  case requesting
  case denied
  case restricted
  case loaded
  case loading
  case failed
}

package nonisolated enum NearbyPlacesStatus: Equatable, Sendable {
  case idle
  case loading
  case loaded
  case failed
}

@Reducer
package struct SetupLocationPickerFeature {
  @ObservableState
  package struct State: Equatable {
    package var currentLocation: GameLocation?
    package var selectedLocation: GameLocation?
    package var places: [NearbyPlace]
    package var status: NearbyPlacesStatus
    package var locationStatus: SetupLocationStatus
  }

  package enum Action {
    case closeButtonTapped
    case currentLocationTapped
    case placeTapped(NearbyPlace.ID)
    case retryButtonTapped
  }

  package var body: some Reducer<State, Action> {
    EmptyReducer<State, Action>()
  }
}
