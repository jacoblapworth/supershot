import AppSettings
import AppUI
import ComposableArchitecture
import Database
import GameAnalysis
import GameCore
import GameServices
import LocationClient
import MapKit
import PermissionsFeature
import PreviewSupport
import ScoringFeature
import SharedModels
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import UI

#if os(iOS)
  import UIKit
#endif

package struct SetupLocationView: View {
  @Environment(\.openURL) private var openURL
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  package let store: StoreOf<NewGameFeature>

  package var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      SetupLocationMap(
        currentLocation: store.currentLocation,
        selectedLocation: store.selectedLocation
      )

      if store.selectedLocation != nil || store.currentLocation != nil {
        let layout = dynamicTypeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
          : AnyLayout(HStackLayout(spacing: 12))
        layout {
          Label(locationTitle, systemImage: "mappin.and.ellipse")
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: 0)
          }
          HStack(spacing: 16) {
            Button("Change") { store.send(.changeLocationButtonTapped) }
              .buttonStyle(.borderless)
              .accessibilityLabel("Change game location")
            Button("Refresh", systemImage: "arrow.clockwise") { store.send(.locationButtonTapped) }
              .buttonStyle(.borderless)
              .labelStyle(.iconOnly)
              .disabled(store.location == .loading || store.location == .requesting)
          }
        }
      }

      switch store.location {
      case .idle:
        HStack {
          Label("Current location", systemImage: "mappin.and.ellipse")
          Spacer()
          Button("Add") { store.send(.locationButtonTapped) }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add current location")
        }

      case .denied:
        Text("Allow location access to save where you played.")
          .foregroundStyle(.secondary)
        #if os(iOS)
          Button("Open Settings") {
            openURL(URL(string: UIApplication.openSettingsURLString)!)
          }
          .buttonStyle(.bordered)
        #else
          Button("Open Settings") {
            openURL(URL(string: "x-apple.systempreferences:")!)
          }
          .buttonStyle(.bordered)
          Text("Allow location access for Supershot in Privacy & Security → Location Services.")
            .font(.caption).foregroundStyle(.secondary)
        #endif

      case .restricted:
        Text("Location access is restricted on this device. You can start the game without a location.")
          .foregroundStyle(.secondary)

      case .requesting, .loading:
        HStack(spacing: 12) {
          ProgressView()
          Text(store.location == .requesting ? "Requesting access…" : "Finding your current location…")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

      case .loaded:
        switch store.nearbyPlacesStatus {
        case .loading:
          ProgressView("Finding nearby places…")
            .font(.subheadline)
        case .failed:
          Text("Couldn’t load nearby places. Your game location is still available.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Button("Try again") { store.send(.changeLocationButtonTapped) }
            .buttonStyle(.borderless)
        case .idle, .loaded:
          EmptyView()
        }

      case .failed:
        VStack(alignment: .leading, spacing: 12) {
          Label(
            "Couldn’t find your location. You can start the game without it.",
            systemImage: "location.slash"
          )
          .foregroundStyle(.secondary)
          Button("Try again") { store.send(.locationButtonTapped) }
            .buttonStyle(.bordered)
        }
      }
    }
    .setupCardStyle()
  }

  private var locationTitle: String {
    guard let location = store.selectedLocation else { return String(localized: "Choose game location") }
    return location.pointOfInterestName ?? String(localized: "Current location")
  }

  package init(store: StoreOf<NewGameFeature>) {
    self.store = store
  }
}

#Preview("Loaded") {
  var state = NewGameFeature.State.previewReady
  let _ = {
    state.location = .loaded
    state.currentLocation = LocationClient.previewCoordinates
    state.selectedLocation = LocationClient.previewLocation
  }()
  SetupLocationView(store: setupPreviewStore(state))
    .padding()
}

#Preview("Loading") {
  var state = NewGameFeature.State.previewReady
  let _ = { state.location = .loading }()
  SetupLocationView(store: setupPreviewStore(state))
    .padding()
}

#Preview("Idle") {
  var state = NewGameFeature.State.previewReady
  let _ = { state.location = .idle }()
  SetupLocationView(store: setupPreviewStore(state))
    .padding()
}

#Preview("Unavailable") {
  var state = NewGameFeature.State()
  let _ = { state.location = .failed }()
  SetupLocationView(store: setupPreviewStore(state))
    .padding()
}

private struct SetupLocationMap: View {
  var currentLocation: GameLocation?
  var selectedLocation: GameLocation?
  @State private var position = MapCameraPosition.automatic

  var body: some View {
    Map(position: $position, interactionModes: []) {
      if let currentLocation {
        Annotation("Current location", coordinate: coordinate(currentLocation)) {
          Circle()
            .fill(.blue)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(radius: 2)
            .accessibilityLabel("Current location")
        }
        .annotationTitles(.hidden)
      }
      if let selectedLocation {
        Marker(
          selectedLocation.pointOfInterestName ?? String(localized: "Game location"),
          coordinate: coordinate(selectedLocation)
        )
      }
    }
    .frame(height: 200)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .accessibilityLabel("Game location map")
    .onChange(of: currentLocation, initial: true) { _, _ in updateCamera() }
    .onChange(of: selectedLocation) { _, _ in
      if currentLocation == nil {
        updateCamera()
      }
    }
  }

  private func updateCamera() {
    if let center = currentLocation ?? selectedLocation {
      position = .camera(MapCamera(centerCoordinate: coordinate(center), distance: 800))
    } else {
      position = .automatic
    }
  }

  private func coordinate(_ location: GameLocation) -> CLLocationCoordinate2D {
    .init(latitude: location.latitude, longitude: location.longitude)
  }
}
