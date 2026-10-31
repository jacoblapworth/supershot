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

public nonisolated enum AlarmAuthorizationStatus: Equatable, Sendable {
  case authorized
  case denied
  case notDetermined
}

public nonisolated struct AlarmAuthorizationClient: Sendable {
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

public extension DependencyValues {
  @DependencyEntry(
    liveValue: AlarmAuthorizationClient.live,
    previewValue: AlarmAuthorizationClient.authorized
  )
  nonisolated var alarmAuthorization: AlarmAuthorizationClient = .authorized
}

public nonisolated extension AlarmAuthorizationClient {
  static let authorized = Self(
    request: { .authorized },
    status: { .authorized }
  )

  static var live: Self {
    #if os(iOS)
      Self(
        request: {
          try await AlarmAuthorizationStatus(AlarmManager.shared.requestAuthorization())
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
  fileprivate nonisolated extension AlarmAuthorizationStatus {
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

#if os(macOS)
  package nonisolated func macNotificationAuthorization() async -> AlarmAuthorizationStatus {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral: return .authorized
    case .denied: return .denied
    case .notDetermined: return .notDetermined
    @unknown default: return .notDetermined
    }
  }
#endif
