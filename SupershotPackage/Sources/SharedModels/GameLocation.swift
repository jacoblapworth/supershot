import Foundation

public nonisolated struct GameLocation: Equatable, Hashable, Sendable {
  public var latitude: Double
  public var longitude: Double
  public var pointOfInterestName: String?

  public init(latitude: Double, longitude: Double, pointOfInterestName: String? = nil) {
    self.latitude = latitude
    self.longitude = longitude
    self.pointOfInterestName = pointOfInterestName
  }
}
