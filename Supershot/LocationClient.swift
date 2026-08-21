import CoreLocation
import Dependencies
import Foundation
import MapKit

nonisolated enum LocationAuthorizationStatus: Equatable, Sendable {
  case authorized
  case denied
  case notDetermined
}

nonisolated struct GameLocation: Equatable, Hashable, Sendable {
  var latitude: Double
  var longitude: Double
  var pointOfInterestName: String?
}

nonisolated struct LocationClient: Sendable {
  var authorizationStatus: @Sendable () -> LocationAuthorizationStatus
  var currentLocation: @Sendable () async throws -> GameLocation
  var requestAuthorization: @Sendable () async -> LocationAuthorizationStatus
}

extension DependencyValues {
  nonisolated var locationClient: LocationClient {
    get { self[LocationClientKey.self] }
    set { self[LocationClientKey.self] = newValue }
  }
}

private nonisolated enum LocationClientKey: DependencyKey {
  static var liveValue: LocationClient { .live }
  static var previewValue: LocationClient { .preview }
  static var testValue: LocationClient { .unavailable }
}

nonisolated extension LocationClient {
  static let previewLocation = GameLocation(
    latitude: 51.5560,
    longitude: -0.2796,
    pointOfInterestName: "Wembley Arena"
  )

  static let preview = Self(
    authorizationStatus: { .authorized },
    currentLocation: { previewLocation },
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
        let request = MKLocalPointsOfInterestRequest(
          center: location.coordinate,
          radius: 5_000
        )
        let response = try? await MKLocalSearch(request: request).start()
        let nearestPointOfInterest = response?.mapItems
          .filter { item in
            guard let name = item.name else { return false }
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          }
          .min { lhs, rhs in
            location.distance(from: lhs.location) < location.distance(from: rhs.location)
          }

        return GameLocation(
          latitude: location.coordinate.latitude,
          longitude: location.coordinate.longitude,
          pointOfInterestName: nearestPointOfInterest?.name
        )
      },
      requestAuthorization: {
        let provider = await LocationProvider()
        return await provider.requestAuthorization()
      }
    )
  }
}

nonisolated enum LocationClientError: Error {
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

    return try await withCheckedThrowingContinuation { continuation in
      locationContinuation = continuation
      manager.requestLocation()
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

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 }) else {
      locationContinuation?.resume(throwing: LocationClientError.locationUnavailable)
      locationContinuation = nil
      return
    }
    locationContinuation?.resume(returning: location)
    locationContinuation = nil
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    locationContinuation?.resume(throwing: error)
    locationContinuation = nil
  }
}

private nonisolated extension CLAuthorizationStatus {
  var isAuthorized: Bool {
    self == .authorizedAlways || self == .authorizedWhenInUse
  }
}

private nonisolated extension LocationAuthorizationStatus {
  init(_ status: CLAuthorizationStatus) {
    switch status {
    case .authorizedAlways, .authorizedWhenInUse:
      self = .authorized
    case .denied, .restricted:
      self = .denied
    case .notDetermined:
      self = .notDetermined
    @unknown default:
      self = .notDetermined
    }
  }
}
