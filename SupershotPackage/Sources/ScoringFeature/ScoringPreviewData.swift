import AlarmClient
import AppSettings
import ComposableArchitecture
import Database
import Foundation
import GameAnalysis
import GameCore
import GameServices
import PermissionsFeature
import PreviewSupport
import SharedModels
import SoundEffectsClient
import Styleguide
import SubscriptionClient
import SwiftUI
import WidgetSupport

extension ScoringFeature.Team {
  static package let previewRavens = Self(
    id: UUID(3),
    bibColor: ColorPalette.green,
    name: "Foxes"
  )
  static package let previewSwifts = Self(
    id: UUID(4),
    bibColor: ColorPalette.orange,
    name: "Owls"
  )
}

extension ScoringFeature.State {
  static package var previewQuarter: Self {
    Self(
      centrePassTeamID: ScoringFeature.Team.previewRavens.id,
      currentPhaseIndex: 2,
      gameID: UUID(11),
      periods: MockGameData.periods(gameID: UUID(11), idOffset: 1_010),
      startedAt: Date(),
      teamA: .previewRavens,
      teamB: .previewSwifts,
      teamBScore: 1
    )
  }

  static package var previewQuarterComplete: Self {
    var state = previewQuarter
    state.canUndo = true
    state.elapsedSeconds = state.currentDurationSeconds
    state.isShowingLastCentrePassBanner = true
    state.teamAScore = 38
    state.teamBScore = 38
    return state
  }

  static package var previewBreak: Self {
    var state = previewQuarter
    state.currentPhaseIndex = 3
    state.lateScoringPeriodNumber = 2
    state.isShowingLastCentrePassBanner = true
    state.elapsedSeconds = 0
    state.teamAScore = 19
    state.teamBScore = 19
    return state
  }
}

@MainActor
package func scoringPreviewStore(
  _ state: ScoringFeature.State
) -> StoreOf<ScoringFeature> {
  Store(initialState: state) {
    ScoringFeature()
  }
}
