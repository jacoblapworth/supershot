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

  @Parameter(title: "Period") var expectedPeriod: Int
  @Parameter(title: "Game") var gameID: String

  init() {}

  init(gameID: UUID, expectedPeriod: Int) {
    self.expectedPeriod = expectedPeriod
    self.gameID = gameID.uuidString
  }

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let gameTimer = DependencyValues._current.gameTimer
    if let gameID = UUID(uuidString: gameID) {
      _ = try? await gameTimer.pause(gameID, expectedPeriod)
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

  @Parameter(title: "Period") var expectedPeriod: Int
  @Parameter(title: "Game") var gameID: String

  init() {}

  init(gameID: UUID, expectedPeriod: Int) {
    self.expectedPeriod = expectedPeriod
    self.gameID = gameID.uuidString
  }

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let gameTimer = DependencyValues._current.gameTimer
    if let gameID = UUID(uuidString: gameID) {
      _ = try? await gameTimer.startOrResume(gameID, expectedPeriod, false)
    }
    #endif
    return .result()
  }
}
#endif
