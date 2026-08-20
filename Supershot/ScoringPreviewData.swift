#if DEBUG
import ComposableArchitecture
import Foundation

extension ScoringFeature.Team {
  static let previewRavens = Self(
    id: UUID(3),
    bibColorHex: "#34C759",
    name: "Foxes"
  )
  static let previewSwifts = Self(
    id: UUID(4),
    bibColorHex: "#FF9500",
    name: "Owls"
  )
}

extension ScoringFeature.State {
  static var previewQuarter: Self {
    Self(
      centrePassTeamID: ScoringFeature.Team.previewRavens.id,
      firstBreakDurationSeconds: MockGameData.breakDurationSeconds,
      gameID: UUID(11),
      halfTimeDurationSeconds: MockGameData.breakDurationSeconds,
      period: 2,
      periodDurationSeconds: MockGameData.periodDurationSeconds,
      secondBreakDurationSeconds: MockGameData.breakDurationSeconds,
      startedAt: Date(),
      teamA: .previewRavens,
      teamB: .previewSwifts,
      teamBScore: 1
    )
  }

  static var previewQuarterComplete: Self {
    var state = previewQuarter
    state.canUndo = true
    state.elapsedSeconds = state.periodDurationSeconds
    state.hasTimerStartedThisPeriod = true
    state.isShowingLastCentrePassBanner = true
    state.teamAScore = 38
    state.teamBScore = 38
    return state
  }

  static var previewBreak: Self {
    var state = previewQuarter
    state.clockPhase = .breakTime
    state.elapsedSeconds = state.halfTimeDurationSeconds
    state.hasTimerStartedThisPeriod = true
    state.period = 2
    state.teamAScore = 19
    state.teamBScore = 19
    return state
  }
}

@MainActor
func scoringPreviewStore(
  _ state: ScoringFeature.State
) -> StoreOf<ScoringFeature> {
  Store(initialState: state) {
    ScoringFeature()
  }
}
#endif
