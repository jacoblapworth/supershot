import Dependencies
import Foundation

#if os(iOS)
import ActivityKit
import AlarmKit
import SwiftUI
#endif

nonisolated extension AlarmClient {
  static var live: Self {
    #if os(iOS)
    Self(
      cancelAlarm: { gameID, phaseCount in
        cancelAlarms(for: gameID, phaseCount: phaseCount)
      },
      endActivity: { gameID in
        for activity in Activity<GameActivityAttributes>.activities
        where activity.attributes.gameID == gameID {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
      },
      scheduleAlarm: {
        snapshot,
        requestsAuthorization in
        guard let timerEndsAt = snapshot.game.timerEndsAt else { return false }
        let manager = AlarmManager.shared
        var authorizationState = manager.authorizationState
        if authorizationState == .notDetermined,
           requestsAuthorization {
          authorizationState = (try? await manager.requestAuthorization()) ?? authorizationState
        }
        guard authorizationState == .authorized else {
          return authorizationState == .denied || requestsAuthorization
        }

        cancelAlarms(for: snapshot.game.id, phaseCount: snapshot.phases.count)
        var alarms = [
          ScheduledGameAlarm(
            date: timerEndsAt,
            phase: snapshot.currentPhase,
            phaseIndex: snapshot.game.currentPhaseIndex
          )
        ]
        if
          snapshot.currentPhase.isQuarter,
          snapshot.game.currentPhaseIndex + 1 < snapshot.phases.count
            {
          let breakPhase = snapshot.phases[snapshot.game.currentPhaseIndex + 1]
          if breakPhase.durationSeconds > 0 {
            alarms.append(
              ScheduledGameAlarm(
                date: timerEndsAt.addingTimeInterval(
                  TimeInterval(breakPhase.durationSeconds)
                ),
                phase: breakPhase,
                phaseIndex: snapshot.game.currentPhaseIndex + 1
              )
            )
          }
        }

        for alarm in alarms {
          let presentation = AlarmPresentation(
            alert: AlarmPresentation.Alert(
              title: alarm.title,
              secondaryButton: AlarmButton(
                text: "Continue",
                textColor: .white,
                systemImageName: "play.fill"
              ),
              secondaryButtonBehavior: .custom
            )
          )
          let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: SupershotAlarmMetadata(
              gameID: snapshot.game.id,
              phaseIndex: alarm.phaseIndex
            ),
            tintColor: .green,
          )
          let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(alarm.date),
            attributes: attributes,
            secondaryIntent: OpenGameIntent(gameID: snapshot.game.id)
          )
          do {
            _ = try await manager.schedule(
              id: alarmID(gameID: snapshot.game.id, phaseIndex: alarm.phaseIndex),
              configuration: configuration
            )
          } catch {
            cancelAlarms(for: snapshot.game.id, phaseCount: snapshot.phases.count)
            return true
          }
        }
        return false
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
          (
            snapshot.game.timerEndsAt != nil
              || snapshot.game.elapsedSeconds > 0
              || snapshot.game.currentPhaseIndex > 0
          ),
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
  var phaseIndex: Int
}

private nonisolated struct ScheduledGameAlarm {
  var date: Date
  var phase: GamePhase
  var phaseIndex: Int

  var title: LocalizedStringResource {
    switch phase {
    case let .quarter(number, _):
      "Quarter \(number) ended."
    case .breakTime:
      "Break ended."
    }
  }
}

private nonisolated func cancelAlarms(for gameID: Game.ID, phaseCount: Int) {
  for phaseIndex in 0..<phaseCount {
    let id = alarmID(gameID: gameID, phaseIndex: phaseIndex)
    try? AlarmManager.shared.stop(id: id)
    try? AlarmManager.shared.cancel(id: id)
  }
  try? AlarmManager.shared.stop(id: gameID)
  try? AlarmManager.shared.cancel(id: gameID)
}

private nonisolated func alarmID(gameID: Game.ID, phaseIndex: Int) -> UUID {
  let value = gameID.uuid
  return UUID(
    uuid: (
      value.0, value.1, value.2, value.3,
      value.4, value.5, value.6, value.7,
      value.8, value.9, value.10, value.11,
      value.12, value.13, value.14,
      value.15 ^ UInt8(truncatingIfNeeded: phaseIndex + 1)
    )
  )
}

private nonisolated extension GameActivityAttributes {
  init(snapshot: GameSnapshot) {
    self.init(
      gameID: snapshot.game.id,
      teamAID: snapshot.teamA.id,
      teamAColorHex: snapshot.game.teamABibColorHex,
      teamAName: snapshot.teamA.name,
      teamBID: snapshot.teamB.id,
      teamBColorHex: snapshot.game.teamBBibColorHex,
      teamBName: snapshot.teamB.name
    )
  }
}

private nonisolated extension GameActivityAttributes.ContentState {
  init(snapshot: GameSnapshot) {
    self.init(
      centrePassTeamID: snapshot.game.centrePassTeamID ?? snapshot.teamA.id,
      currentDurationSeconds: snapshot.currentPhase.durationSeconds,
      elapsedSeconds: snapshot.game.elapsedSeconds,
      phaseIndex: snapshot.game.currentPhaseIndex,
      teamAScore: snapshot.teamAScore,
      teamBScore: snapshot.teamBScore,
      timerEndsAt: snapshot.game.timerEndsAt
    )
  }
}
#endif
