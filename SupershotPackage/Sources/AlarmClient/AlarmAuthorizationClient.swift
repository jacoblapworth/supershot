import Database
import Dependencies
import DependenciesMacros
import GameCore
import SharedModels

#if os(iOS)
  import AlarmKit
#endif

nonisolated public enum AlarmAuthorizationStatus: Equatable, Sendable {
  case authorized
  case denied
  case notDetermined
}

nonisolated public struct AlarmAuthorizationClient: Sendable {
  public var request: @Sendable () async throws -> AlarmAuthorizationStatus
  public var status: @Sendable () -> AlarmAuthorizationStatus

  public init(
    request: @escaping @Sendable () async throws -> AlarmAuthorizationStatus,
    status: @escaping @Sendable () -> AlarmAuthorizationStatus
  ) {
    self.request = request
    self.status = status
  }
}

extension DependencyValues {
  @DependencyEntry(
    liveValue: AlarmAuthorizationClient.live,
    previewValue: AlarmAuthorizationClient.authorized
  )
  public var alarmAuthorization: AlarmAuthorizationClient = .authorized
}

nonisolated extension AlarmAuthorizationClient {
  static public let authorized = Self(
    request: { .authorized },
    status: { .authorized }
  )

  static public var live: Self {
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
  nonisolated
    extension AlarmAuthorizationStatus
  {
    fileprivate init(_ state: AlarmManager.AuthorizationState) {
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
