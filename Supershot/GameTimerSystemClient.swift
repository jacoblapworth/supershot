import Dependencies
import Foundation

#if os(iOS)
import ActivityKit
import AlarmKit
import SwiftUI
#endif

nonisolated extension GameTimerSystemClient {
  static var live: Self {
    #if os(iOS)
    Self(
      cancelAlarm: { gameID in
        try? AlarmManager.shared.stop(id: gameID)
        try? AlarmManager.shared.cancel(id: gameID)
      },
      endActivity: { gameID in
        for activity in Activity<GameActivityAttributes>.activities
        where activity.attributes.gameID == gameID {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
      },
      scheduleAlarm: { snapshot, requestsAuthorization in
        guard let timerEndsAt = snapshot.game.timerEndsAt else { return false }
        let manager = AlarmManager.shared
        var authorizationState = manager.authorizationState
        if authorizationState == .notDetermined, requestsAuthorization {
          authorizationState = (try? await manager.requestAuthorization()) ?? authorizationState
        }
        guard authorizationState == .authorized else {
          return authorizationState == .denied || requestsAuthorization
        }

        try? manager.stop(id: snapshot.game.id)
        try? manager.cancel(id: snapshot.game.id)
        let title = LocalizedStringResource(
          "Quarter \(snapshot.game.currentPeriod) ended."
        )
        let presentation = AlarmPresentation(
          alert: AlarmPresentation.Alert(title: title)
        )
        let attributes = AlarmAttributes(
          presentation: presentation,
          metadata: SupershotAlarmMetadata(
            gameID: snapshot.game.id,
            period: snapshot.game.currentPeriod
          ),
          tintColor: .accentColor
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
          schedule: .fixed(timerEndsAt),
          attributes: attributes
        )
        do {
          _ = try await manager.schedule(
            id: snapshot.game.id,
            configuration: configuration
          )
          return false
        } catch {
          return true
        }
      },
      updateActivity: { snapshot, startsIfNeeded in
        guard snapshot.game.endedAt == nil else { return }
        let content = ActivityContent(
          state: GameActivityAttributes.ContentState(snapshot: snapshot),
          staleDate: snapshot.game.timerEndsAt
        )
        if let activity = Activity<GameActivityAttributes>.activities.first(
          where: { $0.attributes.gameID == snapshot.game.id }
        ) {
          await activity.update(content)
        } else if
          startsIfNeeded,
          snapshot.game.hasTimerStartedCurrentPeriod,
          ActivityAuthorizationInfo().areActivitiesEnabled
        {
          _ = try? Activity.request(
            attributes: GameActivityAttributes(snapshot: snapshot),
            content: content,
            pushType: nil
          )
        }
      }
    )
    #else
    .noop
    #endif
  }
}

#if os(iOS)
private nonisolated struct SupershotAlarmMetadata: AlarmMetadata {
  var gameID: UUID
  var period: Int
}

private nonisolated extension GameActivityAttributes {
  init(snapshot: GameSnapshot) {
    self.init(
      gameID: snapshot.game.id,
      teamAColorHex: snapshot.teamA.colorHex,
      teamAName: snapshot.teamA.name,
      teamBColorHex: snapshot.teamB.colorHex,
      teamBName: snapshot.teamB.name
    )
  }
}

private nonisolated extension GameActivityAttributes.ContentState {
  init(snapshot: GameSnapshot) {
    self.init(
      currentDurationSeconds: snapshot.game.currentTimerDurationSeconds,
      elapsedSeconds: snapshot.game.elapsedSeconds,
      isInBreak: snapshot.game.isInBreak,
      period: snapshot.game.currentPeriod,
      teamAScore: snapshot.teamAScore,
      teamBScore: snapshot.teamBScore,
      timerEndsAt: snapshot.game.timerEndsAt
    )
  }
}
#endif
