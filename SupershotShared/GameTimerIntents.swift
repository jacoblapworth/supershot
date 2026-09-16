#if os(iOS)
import AlarmKit
import AppIntents
import Foundation

#if !WIDGET_EXTENSION
import Dependencies
import SQLiteData
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

struct ScoreGoalIntent: LiveActivityIntent {
  static var allowedExecutionTargets: IntentExecutionTargets { .main }
  static var isDiscoverable: Bool { false }
  static var supportedModes: IntentModes { .background }
  static var title: LocalizedStringResource { "Score a goal" }

  @Parameter(title: "Game") var gameID: String
  @Parameter(title: "Team") var teamID: String
  @Parameter(title: "Phase") var expectedPhaseIndex: Int

  init() {}

  init(gameID: UUID, teamID: UUID, expectedPhaseIndex: Int) {
    self.gameID = gameID.uuidString
    self.teamID = teamID.uuidString
    self.expectedPhaseIndex = expectedPhaseIndex
  }

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    guard let gameID = UUID(uuidString: gameID),
      let teamID = UUID(uuidString: teamID)
    else { return .result() }
    @Dependencies.Dependency(\.defaultDatabase) var database
    @Dependencies.Dependency(\.date.now) var now
    @Dependencies.Dependency(\.uuid) var uuid
    @Dependencies.Dependency(\.gameTimer) var gameTimer
    let goalID = uuid()
    let createdAt = now
    let phaseIndex = expectedPhaseIndex
    do {
      _ = try await database.write { db in
        try ScoringFeature.insertGoal(
          db, gameID: gameID, teamID: teamID,
          expectedPhaseIndex: phaseIndex, goalID: goalID, createdAt: createdAt
        )
      }
    } catch {
      _ = try? await gameTimer.reconcile(gameID)
      throw GoalScoringIntentError.unavailable
    }
    await gameTimer.refreshActivity(gameID)
    #endif
    return .result()
  }
}

private enum GoalScoringIntentError: Error, CustomLocalizedStringResourceConvertible {
  case unavailable

  var localizedStringResource: LocalizedStringResource {
    "The goal could not be recorded. Open the game to check the score and timer."
  }
}

struct OpenGameIntent: LiveActivityIntent {
  static var allowedExecutionTargets: IntentExecutionTargets { .main }
  static var isDiscoverable: Bool { false }
  static var supportedModes: IntentModes { .foreground }
  static var title: LocalizedStringResource { "Open game" }

  @Parameter(title: "Game") var gameID: String
  @Parameter(title: "Alarm") var alarmID: String?

  init() {}

  init(gameID: UUID, alarmID: UUID? = nil) {
    self.gameID = gameID.uuidString
    self.alarmID = alarmID?.uuidString
  }

  func perform() async throws -> some IntentResult {
    guard
      let gameID = UUID(uuidString: gameID),
      let gameURL = URL(string: "supershot://game/\(gameID.uuidString)")
    else { return .result() }

    if let alarmID, let alarmID = UUID(uuidString: alarmID) {
      try? AlarmManager.shared.stop(id: alarmID)
    }

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
