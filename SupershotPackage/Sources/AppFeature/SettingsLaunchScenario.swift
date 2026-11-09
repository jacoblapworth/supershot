#if DEBUG
  import AlarmClient
  import AppSettings
  import Database
  import Dependencies
  import Foundation
  import Sharing
  import SQLiteData
  import SubscriptionClient

  /// Explicitly opt in with `--launch-scenario settings-alarm-sounds`.
  public enum SettingsLaunchScenario {
    public static var isRequested: Bool {
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "--launch-scenario") else { return false }
      guard arguments.indices.contains(index + 1), arguments[index + 1] == "settings-alarm-sounds" else {
        preconditionFailure("Unknown launch scenario. Expected settings-alarm-sounds.")
      }
      return true
    }

    /// Run before purchases, widget observation, or the normal persistent database bootstrap.
    public static func prepare() throws {
      let database = try withDependencies {
        $0.context = .preview
      } operation: {
        var values = DependencyValues()
        try values.bootstrapDatabase()
        return values.defaultDatabase
      }
      prepareDependencies {
        $0.defaultDatabase = database
        $0.defaultAppStorage = UserDefaults(suiteName: "Supershot.SettingsAlarmSoundsScenario")!
        $0.proSubscription = .free
        $0.alarmClient = .noop
        $0.alarmAuthorization = .authorized
      }
    }

    package static func initialState() -> AppFeature.State {
      var state = AppFeature.State()
      state.$hasCompletedWelcome.withLock { $0 = true }
      state.destination = nil
      state.selectedTab = .settings
      state.proAccess = .free
      return state
    }
  }
#endif
