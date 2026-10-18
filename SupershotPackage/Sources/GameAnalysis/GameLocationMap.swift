import CoreLocation
import Database
import GameCore
import LocationClient
import MapKit
import PaywallFeature
import PreviewSupport
import SharedModels
import Styleguide
import SwiftUI
import WidgetSupport

package struct GameLocationMap: View {
  package var location: GameLocation

  package var body: some View {
    Map(
      initialPosition: .camera(
        MapCamera(
          centerCoordinate: coordinate,
          distance: 800
        )
      ),
      interactionModes: []
    ) {
      if let pointOfInterestName = location.pointOfInterestName {
        Marker(pointOfInterestName, coordinate: coordinate)
      } else {
        Marker("Game location", coordinate: coordinate)
      }
    }
    .frame(height: 200)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    location.pointOfInterestName ?? String(localized: "Game location")
  }

  private var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(
      latitude: location.latitude,
      longitude: location.longitude
    )
  }

  package init(location: GameLocation) {
    self.location = location
  }
}

#Preview("Named location") {
  GameLocationMap(location: LocationClient.previewLocation)
    .padding()
}

#Preview("Unnamed location") {
  GameLocationMap(
    location: GameLocation(
      latitude: 51.5560,
      longitude: -0.2796,
      pointOfInterestName: nil
    )
  )
  .padding()
}
