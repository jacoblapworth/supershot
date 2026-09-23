//
//  ScoreGoalIntent.swift
//  Supershot
//
//  Created by J on 16/09/2026.
//


#if os(iOS)
import AlarmKit
import AppIntents
import Foundation

#if !WIDGET_EXTENSION
import Dependencies
import SQLiteData
#endif

struct ScoreGoalIntent: LiveActivityIntent {
  static var allowedExecutionTargets: IntentExecutionTargets { [.main, .widgetKitExtension, .appIntentsExtension] }
  static var isDiscoverable: Bool { false }
  static var supportedModes: IntentModes { .background }
  static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
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

#endif
