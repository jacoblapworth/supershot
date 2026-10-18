import AlarmClient
import AppSettings
import Database
import GameAnalysis
import GameCore
import GameServices
import PermissionsFeature
import PreviewSupport
import SharedModels
import SoundEffectsClient
import Styleguide
import SubscriptionClient
import WidgetSupport

extension ScoringFeature.State {
  package init(snapshot: GameSnapshot) {
    let currentPhaseIndex = snapshot.game.currentPhaseIndex
    let currentDuration = snapshot.currentPhase.durationSeconds

    self.init(
      canUndo: !snapshot.goals.isEmpty,
      canUndoDuringConfirmation: snapshot.canUndoDuringConfirmation,
      centrePassTeamID: snapshot.game.centrePassTeamID == snapshot.teamB.id
        ? snapshot.teamB.id
        : snapshot.teamA.id,
      currentPhaseIndex: currentPhaseIndex,
      elapsedSeconds: min(
        max(snapshot.game.elapsedSeconds, 0),
        max(currentDuration, 0)
      ),
      swapSides: snapshot.game.swapSides,
      gameID: snapshot.game.id,
      isShowingLastCentrePassBanner: snapshot.game.isAwaitingCentrePassConfirmation,
      lateScoringPeriodNumber: snapshot.game.lateScoringPeriodNumber,
      periods: snapshot.periods,
      startedAt: snapshot.game.startedAt,
      teamA: ScoringFeature.Team(
        id: snapshot.teamA.id,
        bibColor: snapshot.game.teamABibColor,
        name: snapshot.teamA.name
      ),
      teamAScore: snapshot.teamAScore,
      teamB: ScoringFeature.Team(
        id: snapshot.teamB.id,
        bibColor: snapshot.game.teamBBibColor,
        name: snapshot.teamB.name
      ),
      teamBScore: snapshot.teamBScore,
      timerEndsAt: snapshot.game.timerEndsAt
    )
  }
}
