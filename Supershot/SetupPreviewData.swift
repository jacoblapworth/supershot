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

extension TeamSlotFeature.State {
  static var previewChoosing: Self {
    var state = Self(side: .left)
    state.mode = .choosing
    return state
  }

  static var previewCreating: Self {
    var state = Self(side: .left)
    state.editor.name = "Falcons"
    state.mode = .creating
    return state
  }

  static var previewEditing: Self {
    var state = Self(side: .left)
    state.editor = TeamSlotFeature.TeamDraft(
      colorHex: "#34C759",
      name: Team.previewRavens.name
    )
    state.mode = .editing
    state.selection = .existing(
      original: .previewRavens,
      draft: state.editor
    )
    return state
  }
}

extension NewGameFeature.State {
  static var previewReady: Self {
    var state = Self()
    state.availableTeams = .previewTeams
    state.didLoadTeams = true
    state.firstCentrePass = .teamA
    state.leftTeam.mode = .locked
    state.leftTeam.selection = .existing(
      original: .previewRavens,
      draft: TeamSlotFeature.TeamDraft(
        colorHex: Team.previewRavens.colorHex,
        name: Team.previewRavens.name
      )
    )
    state.rightTeam.mode = .locked
    state.rightTeam.selection = .existing(
      original: .previewSwifts,
      draft: TeamSlotFeature.TeamDraft(
        colorHex: Team.previewSwifts.colorHex,
        name: Team.previewSwifts.name
      )
    )
    return state
  }

  static var previewLoading: Self {
    var state = Self()
    state.isLoadingTeams = true
    return state
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
