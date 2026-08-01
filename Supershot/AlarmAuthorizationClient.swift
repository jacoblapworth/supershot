import Dependencies

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
  nonisolated var alarmAuthorization: AlarmAuthorizationClient {
    get { self[AlarmAuthorizationClientKey.self] }
    set { self[AlarmAuthorizationClientKey.self] = newValue }
  }
}

private nonisolated enum AlarmAuthorizationClientKey: DependencyKey {
  static var liveValue: AlarmAuthorizationClient {
    .live
  }

  static var previewValue: AlarmAuthorizationClient {
    .authorized
  }

  static var testValue: AlarmAuthorizationClient {
    .authorized
  }
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
