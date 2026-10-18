import AppSettings
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
import Styleguide
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import WidgetSupport

extension NewGameFeature.State {
  static package var previewReady: Self {
    var state = Self()
    state.firstCentrePass = .teamA
    state.leftTeam.team = Team.previewRavens
    state.rightTeam.team = Team.previewSwifts
    return state
  }

  static package var previewLoading: Self {
    Self()
  }

  static package var previewCustomTiming: Self {
    var state = Self()
    state.customizesBreaks = true
    state.firstBreakDuration = .init(totalSeconds: 120)
    state.halfTimeDuration = .init(totalSeconds: 600)
    state.secondBreakDuration = .init(totalSeconds: 180)
    return state
  }

  static package var previewInvalidTiming: Self {
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
