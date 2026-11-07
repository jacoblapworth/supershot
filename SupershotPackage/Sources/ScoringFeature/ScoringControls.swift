import Foundation
import GameCore
import SharedModels

package enum ScoringControlAction: Hashable {
  case startOrResume
  case pause
  case skipBreak
  case finishGame
  case editTime
  case endQuarter
  case changeCentrePass
  case swapSides
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
  package var waitingSince: Date?
  package var editTime: ScoringControl?
  package var controls: [ScoringControl]
}

package struct CentrePassConfirmationState: Equatable {
  package var period: Int
  package var availability: ScoringControl.Availability
}

package struct ScoringToolbarState: Equatable {
  package struct SheetReveal: Equatable {
    package var phaseIndex: Int
    package var action: ScoringControlAction
  }

  package enum Content: Equatable {
    case none
    case primary(ScoringControl)
    case confirmation(CentrePassConfirmationState)
  }

  package var content: Content
  package var courtLayout: ScoringFeature.CourtLayout
  package var canScore: Bool
  package var sheetPrimaryControl: ScoringControl?
  package var sheetReveal: SheetReveal?
  package var additionalControls: [ScoringControl]
  package var phaseIndex: Int
  package var isTimerRunning: Bool

  package func shouldCollapse(after previous: Self) -> Bool {
    previous.sheetReveal?.action == .startOrResume
      && previous.sheetReveal?.phaseIndex == phaseIndex
      && sheetReveal == nil && isTimerRunning
  }
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
      title: waitingSince != nil
        ? "Waiting for Quarter \(period)"
        : currentPhase.isBreak ? "Quarter \(period) break" : "Quarter \(period)",
      remainingSeconds: timeRemainingSeconds,
      elapsedSeconds: timerProjection.elapsedSeconds,
      durationSeconds: currentDurationSeconds,
      waitingSince: waitingSince,
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
    if isAwaitingCentrePassConfirmation {
      content = .confirmation(.init(
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
    } else if operation == .pausing(phaseIndex: currentPhaseIndex)
      || operation == .skipping(phaseIndex: currentPhaseIndex)
    {
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
    let primary: ScoringControl? = if case let .primary(control) = content {
      control
    } else if currentPhase.isBreak, operation != .skipping(phaseIndex: currentPhaseIndex) {
      timerViewState.controls.first { $0.action == .startOrResume }
    } else {
      nil
    }
    var additional = timerViewState.controls.filter { $0.action != primary?.action }
    if let editTime = timerViewState.editTime {
      additional.append(editTime)
    }
    if currentPhase.isPlayingPeriod {
      additional.append(.init(
        title: "End Quarter",
        systemImage: "forward.end.fill",
        action: .endQuarter,
        availability: canMoveToNextQuarter ? .enabled : .disabled
      ))
    }
    additional.append(.init(
      title: "Change centre pass",
      systemImage: "arrow.left.circle.fill",
      action: .changeCentrePass,
      availability: canOperate ? .enabled : .disabled
    ))
    additional.append(.init(
      title: "Swap sides",
      systemImage: "arrow.left.arrow.right",
      action: .swapSides,
      availability: isSavingCourtOrientation ? .pending : canOperate ? .enabled : .disabled
    ))
    return ScoringToolbarState(
      content: content,
      courtLayout: courtLayout,
      canScore: canScoreGoal,
      sheetPrimaryControl: primary,
      sheetReveal: primary.map { .init(phaseIndex: currentPhaseIndex, action: $0.action) },
      additionalControls: additional,
      phaseIndex: currentPhaseIndex,
      isTimerRunning: isTimerRunning
    )
  }
}

/// Translate shared view controls at the boundary without forwarding reducer actions.
package extension ScoringFeature.Action {
  init(control: ScoringControlAction) {
    switch control {
    case .startOrResume: self = .startTimerButtonTapped
    case .pause: self = .pauseTimerButtonTapped
    case .skipBreak: self = .skipBreakButtonTapped
    case .finishGame: self = .finishGameButtonTapped
    case .editTime: self = .editTimeButtonTapped
    case .endQuarter: self = .endQuarterButtonTapped
    case .changeCentrePass: self = .changeCentrePassButtonTapped
    case .swapSides: self = .swapSidesButtonTapped
    case let .goal(teamID): self = .goalButtonTapped(teamID)
    case let .confirmCentrePass(wasTaken): self = .centrePassConfirmed(wasTaken)
    }
  }
}
