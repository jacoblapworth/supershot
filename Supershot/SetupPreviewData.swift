#if DEBUG
import ComposableArchitecture
import Foundation

extension Team {
  static let previewRavens = Self(
    id: UUID(),
    name: "North London Ravens",
    colorHex: TeamColorPalette.blue
  )
  static let previewSwifts = Self(
    id: UUID(),
    name: "Westminster Swifts",
    colorHex: TeamColorPalette.red
  )
  static let previewFoxes = Self(
    id: UUID(),
    name: "Foxes",
    colorHex: "#34C759"
  )
}

extension Array where Element == Team {
  static var previewTeams: Self {
    [
      Team.previewRavens,
      Team.previewSwifts,
      Team.previewFoxes,
    ]
  }
}

extension NewGameFeature.State {
  static var previewReady: Self {
    var state = Self()
    state.firstCentrePass = .teamA
    state.leftTeam.team = Team.previewRavens
    state.rightTeam.team = Team.previewSwifts
    return state
  }

  static var previewLoading: Self {
    Self()
  }

  static var previewCustomTiming: Self {
    var state = Self()
    state.customizesBreaks = true
    state.firstBreakDuration = .init(totalSeconds: 120)
    state.halfTimeDuration = .init(totalSeconds: 600)
    state.secondBreakDuration = .init(totalSeconds: 180)
    return state
  }

  static var previewInvalidTiming: Self {
    var state = Self()
    state.periodDuration.minutesText = "abc"
    state.periodDuration.secondsText = "75"
    return state
  }
}

@MainActor
func setupPreviewStore() -> StoreOf<NewGameFeature> {
  setupPreviewStore(NewGameFeature.State())
}

@MainActor
func setupPreviewStore(_ state: NewGameFeature.State) -> StoreOf<NewGameFeature> {
  Store(initialState: state) {
    NewGameFeature()
  }
}
#endif
