import Database
import Dependencies
import DependenciesMacros
import GameCore
import SharedModels
#if os(macOS)
  import UserNotifications
#endif

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
  public var status: @Sendable () async -> AlarmAuthorizationStatus

  public init(
    request: @escaping @Sendable () async throws -> AlarmAuthorizationStatus,
    status: @escaping @Sendable () async -> AlarmAuthorizationStatus
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
    #elseif os(macOS)
      Self(
        request: {
          _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
          return await macNotificationAuthorization()
        },
        status: { await macNotificationAuthorization() }
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

#if os(macOS)
nonisolated package func macNotificationAuthorization() async -> AlarmAuthorizationStatus {
  let settings = await UNUserNotificationCenter.current().notificationSettings()
  switch settings.authorizationStatus {
  case .authorized, .provisional, .ephemeral: return .authorized
  case .denied: return .denied
  case .notDetermined: return .notDetermined
  @unknown default: return .notDetermined
  }
}
#endif
