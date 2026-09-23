//
//  OpenGameIntent.swift
//  Supershot
//
//  Created by J on 16/09/2026.
//


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
