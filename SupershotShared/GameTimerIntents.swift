#if os(iOS)
import AppIntents
import Foundation

#if !WIDGET_EXTENSION
import Dependencies
#endif

struct PauseGameTimerIntent: LiveActivityIntent {
  static var allowedExecutionTargets: IntentExecutionTargets { .main }
  static var isDiscoverable: Bool { false }
  static var supportedModes: IntentModes { .background }
  static var title: LocalizedStringResource { "Pause game timer" }

  @Parameter(title: "Phase") var expectedPhaseIndex: Int
  @Parameter(title: "Game") var gameID: String

  init() {}

  init(gameID: UUID, expectedPhaseIndex: Int) {
    self.expectedPhaseIndex = expectedPhaseIndex
    self.gameID = gameID.uuidString
  }

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let gameTimer = DependencyValues._current.gameTimer
    if let gameID = UUID(uuidString: gameID) {
      _ = try? await gameTimer.pause(gameID, expectedPhaseIndex)
    }
    #endif
    return .result()
  }
}

struct ResumeGameTimerIntent: LiveActivityIntent {
  static var allowedExecutionTargets: IntentExecutionTargets { .main }
  static var isDiscoverable: Bool { false }
  static var supportedModes: IntentModes { .background }
  static var title: LocalizedStringResource { "Resume game timer" }

  @Parameter(title: "Phase") var expectedPhaseIndex: Int
  @Parameter(title: "Game") var gameID: String

  init() {}

  init(gameID: UUID, expectedPhaseIndex: Int) {
    self.expectedPhaseIndex = expectedPhaseIndex
    self.gameID = gameID.uuidString
  }

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let gameTimer = DependencyValues._current.gameTimer
    if let gameID = UUID(uuidString: gameID) {
      _ = try? await gameTimer.startOrResume(gameID, expectedPhaseIndex, false)
    }
    #endif
    return .result()
  }
}

struct OpenGameIntent: LiveActivityIntent {
  static var allowedExecutionTargets: IntentExecutionTargets { .main }
  static var isDiscoverable: Bool { false }
  static var supportedModes: IntentModes { .foreground }
  static var title: LocalizedStringResource { "Open game" }

  @Parameter(title: "Game") var gameID: String

  init() {}

  init(gameID: UUID) {
    self.gameID = gameID.uuidString
  }

  func perform() async throws -> some IntentResult {
    guard
      let gameID = UUID(uuidString: gameID),
      let gameURL = URL(string: "supershot://game/\(gameID.uuidString)")
    else { return .result() }

    await MainActor.run {
      NotificationCenter.default.post(name: .openSupershotGame, object: gameURL)
    }
    return .result()
  }
}

extension Notification.Name {
  static let openSupershotGame = Self("OpenSupershotGame")
}
#endif
