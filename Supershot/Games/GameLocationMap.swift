import CoreLocation
import MapKit
import SwiftUI

struct GameLocationMap: View {
  var location: GameLocation

  var body: some View {
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
