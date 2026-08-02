#if DEBUG
import ComposableArchitecture
import Foundation

extension ScoringFeature.Team {
  static let previewRavens = Self(
    id: UUID(),
    bibColorHex: TeamColorPalette.blue,
    name: "North London Ravens"
  )
  static let previewSwifts = Self(
    id: UUID(),
    bibColorHex: TeamColorPalette.red,
    name: "Westminster Swifts"
  )
}

extension ScoringFeature.State {
  static var previewQuarter: Self {
    Self(
      centrePassTeamID: ScoringFeature.Team.previewRavens.id,
      firstBreakDurationSeconds: 240,
      gameID: UUID(),
      halfTimeDurationSeconds: 600,
      secondBreakDurationSeconds: 240,
      startedAt: Date(),
      teamA: .previewRavens,
      teamB: .previewSwifts
    )
  }

  static var previewQuarterComplete: Self {
    var state = previewQuarter
    state.canUndo = true
    state.elapsedSeconds = state.periodDurationSeconds
    state.hasTimerStartedThisPeriod = true
    state.isShowingLastCentrePassBanner = true
    state.teamAScore = 18
    state.teamBScore = 16
    return state
  }

  static var previewBreak: Self {
    var state = previewQuarter
    state.clockPhase = .breakTime
    state.elapsedSeconds = state.halfTimeDurationSeconds
    state.hasTimerStartedThisPeriod = true
    state.period = 2
    state.teamAScore = 26
    state.teamBScore = 24
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
