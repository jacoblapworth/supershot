import Foundation
import GameCore
import SharedModels

package enum ScoringControlAction: Equatable {
  case startOrResume
  case pause
  case skipBreak
  case finishGame
  case editTime
  case goal(UUID)
  case confirmCentrePass(Bool)
}

package struct ScoringControl: Equatable {
  package enum Availability: Equatable { case enabled, disabled, pending }
  package var title: String
  package var systemImage: String
  package var action: ScoringControlAction
  package var availability: Availability
}

package struct TimerViewState: Equatable {
  package var title: String
  package var remainingSeconds: Int
  package var elapsedSeconds: Int
  package var durationSeconds: Int
  package var editTime: ScoringControl?
  package var controls: [ScoringControl]
}

package struct CentrePassConfirmationState: Equatable {
  package var team: ScoringFeature.Team
  package var period: Int
  package var availability: ScoringControl.Availability
}

package struct ScoringToolbarState: Equatable {
  package enum Content: Equatable {
    case none
    case primary(ScoringControl)
    case confirmation(CentrePassConfirmationState)
  }

  package var content: Content
  package var courtLayout: ScoringFeature.CourtLayout
  package var canScore: Bool
}

package extension ScoringFeature.State {
  var phaseStatus: GameTimingState.PhaseStatus {
    let timing = GameTimingState(phaseIndex: currentPhaseIndex, countdown: countdown)
    guard let status = timing.status(in: timeline) else {
      preconditionFailure("Scoring phase must belong to its timeline")
    }
    return status
  }

  var timerViewState: TimerViewState {
    var controls: [ScoringControl] = []
    if operation == .pausing(phaseIndex: currentPhaseIndex) {
      controls.append(.init(title: "Pause", systemImage: "pause.fill", action: .pause, availability: .pending))
    } else {
      switch phaseStatus {
      case .running:
        controls.append(.init(
          title: "Pause",
          systemImage: "pause.fill",
          action: .pause,
          availability: canPause ? .enabled : .disabled
        ))
      case .paused:
        controls.append(.init(
          title: "Resume",
          systemImage: "play.fill",
          action: .startOrResume,
          availability: operation == .starting(phaseIndex: currentPhaseIndex)
            ? .pending
            : canStartOrResume ? .enabled : .disabled
        ))
      case .ready where currentPhase.isBreak:
        controls.append(.init(
          title: "Start break",
          systemImage: "play.fill",
          action: .startOrResume,
          availability: operation == .starting(phaseIndex: currentPhaseIndex)
            ? .pending
            : canStartOrResume ? .enabled : .disabled
        ))
      case .ready, .complete:
        break
      }
    }
    if currentPhase.isBreak {
      controls.append(.init(
        title: "Skip break",
        systemImage: "forward.end.fill",
        action: .skipBreak,
        availability: operation == .skipping(phaseIndex: currentPhaseIndex)
          ? .pending
          : canSkipBreak ? .enabled : .disabled
      ))
    }
    return TimerViewState(
      title: currentPhase.isBreak ? "Quarter \(period) break" : "Quarter \(period)",
      remainingSeconds: timeRemainingSeconds,
      elapsedSeconds: timerProjection.elapsedSeconds,
      durationSeconds: currentDurationSeconds,
      editTime: canEditTime && controlsAreAvailable
        ? .init(
          title: "Edit remaining time",
          systemImage: "pencil",
          action: .editTime,
          availability: .enabled
        )
        : nil,
      controls: controls
    )
  }

  var scoringToolbarState: ScoringToolbarState {
    let content: ScoringToolbarState.Content
    if isShowingLastCentrePassBanner {
      content = .confirmation(.init(
        team: centrePassTeam,
        period: lastCompletedQuarterNumber,
        availability: operation == .confirmingCentrePass(period: lastCompletedQuarterNumber)
          ? .pending
          : canOperate ? .enabled : .disabled
      ))
    } else if GameProgress(
      phaseIndex: currentPhaseIndex,
      countdown: countdown,
      isAwaitingCentrePassConfirmation: false
    ).isFinalPeriodComplete(in: timeline) {
      content = .primary(.init(
        title: "End game",
        systemImage: "flag.checkered",
        action: .finishGame,
        availability: operation == .finishing ? .pending : canFinishGame ? .enabled : .disabled
      ))
    } else if operation == .pausing(phaseIndex: currentPhaseIndex) {
      content = .none
    } else if currentPhase.isPlayingPeriod, phaseStatus == .ready || phaseStatus == .paused {
      let title = startedAt == nil || (period == 1 && phaseStatus == .ready)
        ? "Start game"
        : phaseStatus == .paused ? "Resume" : "Start Quarter \(period)"
      content = .primary(.init(
        title: title,
        systemImage: "play.fill",
        action: .startOrResume,
        availability: operation == .starting(phaseIndex: currentPhaseIndex)
          ? .pending
          : canStartOrResume ? .enabled : .disabled
      ))
    } else {
      content = .none
    }
    return ScoringToolbarState(content: content, courtLayout: courtLayout, canScore: canScoreGoal)
  }
}
