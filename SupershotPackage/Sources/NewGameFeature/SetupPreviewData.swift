import AppSettings
import AppUI
import ComposableArchitecture
import Database
import Foundation
import GameAnalysis
import GameCore
import GameServices
import LocationClient
import PermissionsFeature
import PreviewSupport
import ScoringFeature
import SharedModels
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import UI

package extension NewGameFeature.State {
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
package func setupPreviewStore() -> StoreOf<NewGameFeature> {
  setupPreviewStore(NewGameFeature.State())
}

@MainActor
package func setupPreviewStore(_ state: NewGameFeature.State) -> StoreOf<NewGameFeature> {
  Store(initialState: state) {
    NewGameFeature()
  }
}
