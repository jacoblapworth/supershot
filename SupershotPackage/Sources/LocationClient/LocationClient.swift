import CoreLocation
import Dependencies
import Foundation
import MapKit
import SharedModels

package nonisolated enum LocationAuthorizationStatus: Equatable, Sendable {
  case authorized
  case denied
  case restricted
  case notDetermined
}

package nonisolated struct LocationClient: Sendable {
  package var authorizationStatus: @Sendable () -> LocationAuthorizationStatus
  package var currentLocation: @Sendable () async throws -> GameLocation
  package var nearbyPlaces: @Sendable (GameLocation) async throws -> [NearbyPlace]
  package var requestAuthorization: @Sendable () async -> LocationAuthorizationStatus

  package init(
    authorizationStatus: @escaping @Sendable () -> LocationAuthorizationStatus,
    currentLocation: @escaping @Sendable () async throws -> GameLocation,
    requestAuthorization: @escaping @Sendable () async -> LocationAuthorizationStatus,
    nearbyPlaces: @escaping @Sendable (GameLocation) async throws -> [NearbyPlace] = { _ in [] }
  ) {
    self.authorizationStatus = authorizationStatus
    self.currentLocation = currentLocation
    self.nearbyPlaces = nearbyPlaces
    self.requestAuthorization = requestAuthorization
  }
}

package nonisolated struct NearbyPlace: Equatable, Identifiable, Sendable {
  package var location: GameLocation
  package var distance: Double

  package let id: String

  package init(id: String? = nil, location: GameLocation, distance: Double) {
    self.id = id ?? "\(location.latitude),\(location.longitude):\(location.pointOfInterestName ?? "")"
    self.location = location
    self.distance = distance
  }
}

package extension DependencyValues {
  nonisolated var locationClient: LocationClient {
    get { self[LocationClientKey.self] }
    set { self[LocationClientKey.self] = newValue }
  }
}

private nonisolated enum LocationClientKey: DependencyKey {
  static var liveValue: LocationClient {
    .live
  }

  static var previewValue: LocationClient {
    .preview
  }

  static var testValue: LocationClient {
    .unavailable
  }
}

package nonisolated extension LocationClient {
  static let previewLocation = GameLocation(
    latitude: 51.5560,
    longitude: -0.2796,
    pointOfInterestName: "Wembley Arena"
  )

  static let previewCoordinates = GameLocation(
    latitude: previewLocation.latitude,
    longitude: previewLocation.longitude
  )

  static let preview = Self(
    authorizationStatus: { .authorized },
    currentLocation: { previewCoordinates },
    requestAuthorization: { .authorized }
  )

  static let unavailable = Self(
    authorizationStatus: { .denied },
    currentLocation: { throw LocationClientError.authorizationDenied },
    requestAuthorization: { .denied }
  )

  static var live: Self {
    Self(
      authorizationStatus: {
        LocationAuthorizationStatus(CLLocationManager().authorizationStatus)
      },
      currentLocation: {
        let provider = await LocationProvider()
        guard await provider.authorizationStatus.isAuthorized else {
          throw LocationClientError.authorizationDenied
        }
        let location = try await provider.requestLocation()
        return GameLocation(
          latitude: location.coordinate.latitude,
          longitude: location.coordinate.longitude
        )
      },
      requestAuthorization: {
        let provider = await LocationProvider()
        return await provider.requestAuthorization()
      },
      nearbyPlaces: { location in
        let center = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let request = MKLocalPointsOfInterestRequest(center: center.coordinate, radius: 5000)
        request.pointOfInterestFilter = .init(including: [
          .school,
          .university,
          .fitnessCenter,
          .park,
          .basketball,
          .soccer,
          .stadium,
          .tennis,
          .volleyball,
        ])
        let response = try await MKLocalSearch(request: request).start()
        var seen: Set<NearbyPlace.ID> = []
        return response.mapItems.compactMap { item -> NearbyPlace? in
          guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty else { return nil }
          let place = NearbyPlace(
            id: item.identifier?.rawValue,
            location: GameLocation(
              latitude: item.location.coordinate.latitude,
              longitude: item.location.coordinate.longitude,
              pointOfInterestName: name
            ),
            distance: center.distance(from: item.location)
          )
          return seen.insert(place.id).inserted ? place : nil
        }.sorted {
          $0.distance == $1.distance ? $0.id < $1.id : $0.distance < $1.distance
        }
      }
    )
  }
}

package nonisolated enum LocationClientError: Error {
  case authorizationDenied
  case locationUnavailable
}

@MainActor
private final class LocationProvider: NSObject, CLLocationManagerDelegate {
  private var authorizationContinuation: CheckedContinuation<LocationAuthorizationStatus, Never>?
  private var locationContinuation: CheckedContinuation<CLLocation, any Error>?
  private let manager: CLLocationManager

  override init() {
    manager = CLLocationManager()
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
  }

  var authorizationStatus: CLAuthorizationStatus {
    manager.authorizationStatus
  }

  func requestAuthorization() async -> LocationAuthorizationStatus {
    let status = LocationAuthorizationStatus(manager.authorizationStatus)
    guard status == .notDetermined else { return status }

    return await withCheckedContinuation { continuation in
      authorizationContinuation = continuation
      manager.requestWhenInUseAuthorization()
    }
  }

  func requestLocation() async throws -> CLLocation {
    guard manager.authorizationStatus.isAuthorized else {
      throw LocationClientError.authorizationDenied
    }

    try Task.checkCancellation()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        locationContinuation = continuation
        manager.requestLocation()
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.manager.stopUpdatingLocation()
        self?.locationContinuation?.resume(throwing: CancellationError())
        self?.locationContinuation = nil
      }
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = LocationAuthorizationStatus(manager.authorizationStatus)
    guard status != .notDetermined else { return }
    authorizationContinuation?.resume(returning: status)
    authorizationContinuation = nil

    if status == .denied {
      locationContinuation?.resume(throwing: LocationClientError.authorizationDenied)
      locationContinuation = nil
    }
  }

  func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 }) else {
      locationContinuation?.resume(throwing: LocationClientError.locationUnavailable)
      locationContinuation = nil
      return
    }
    locationContinuation?.resume(returning: location)
    locationContinuation = nil
  }

  func locationManager(_: CLLocationManager, didFailWithError error: any Error) {
    locationContinuation?.resume(throwing: error)
    locationContinuation = nil
  }
}

private nonisolated extension CLAuthorizationStatus {
  var isAuthorized: Bool {
    #if os(iOS)
      self == .authorizedAlways || self == .authorizedWhenInUse
    #else
      self == .authorizedAlways
    #endif
  }
}

private nonisolated extension LocationAuthorizationStatus {
  init(_ status: CLAuthorizationStatus) {
    switch status {
    case .authorizedAlways:
      self = .authorized
    #if os(iOS)
      case .authorizedWhenInUse:
        self = .authorized
    #endif
    case .denied:
      self = .denied
    case .restricted:
      self = .restricted
    case .notDetermined:
      self = .notDetermined
    @unknown default:
      self = .notDetermined
    }
  }
}
