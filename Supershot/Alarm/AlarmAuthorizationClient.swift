import Dependencies
import DependenciesMacros

#if os(iOS)
import AlarmKit
#endif

nonisolated enum AlarmAuthorizationStatus: Equatable, Sendable {
  case authorized
  case denied
  case notDetermined
}

nonisolated struct AlarmAuthorizationClient: Sendable {
  var request: @Sendable () async throws -> AlarmAuthorizationStatus
  var status: @Sendable () -> AlarmAuthorizationStatus
}

extension DependencyValues {
  @DependencyEntry(
    liveValue: AlarmAuthorizationClient.live,
    previewValue: AlarmAuthorizationClient.authorized
  )
  var alarmAuthorization: AlarmAuthorizationClient = .authorized
}

nonisolated extension AlarmAuthorizationClient {
  static let authorized = Self(
    request: { .authorized },
    status: { .authorized }
  )

  static var live: Self {
    #if os(iOS)
    Self(
      request: {
        AlarmAuthorizationStatus(
          try await AlarmManager.shared.requestAuthorization()
        )
      },
      status: {
        AlarmAuthorizationStatus(AlarmManager.shared.authorizationState)
      }
    )
    #else
    .authorized
    #endif
  }
}

#if os(iOS)
private nonisolated extension AlarmAuthorizationStatus {
  init(_ state: AlarmManager.AuthorizationState) {
    switch state {
    case .authorized:
      self = .authorized
    case .denied:
      self = .denied
    case .notDetermined:
      self = .notDetermined
    @unknown default:
      self = .notDetermined
    }
  }
}
#endif
