import Dependencies
import ComposableArchitecture
import CustomDump
import DependenciesTestSupport
import Foundation
import Testing

@testable import Supershot

@MainActor
@Suite(
  .dependencies {
    $0.date.now = Date(timeIntervalSince1970: 1_000)
    $0.uuid = .incrementing
  })
struct ScoringIsolationTests {
  @Test func goalFeedbackUsesStubbedScoringWithoutDatabase() async {
    let state = ScoringFeature.State(
      centrePassTeamID: UUID(1), gameID: UUID(3),
      periods: testGamePeriods(gameID: UUID(3)), startedAt: .distantPast,
      teamA: .init(id: UUID(1), name: "A"), teamB: .init(id: UUID(2), name: "B"),
      timerEndsAt: Date(timeIntervalSince1970: 1_900))
    let store = TestStore(initialState: state) {
      ScoringFeature()
    } withDependencies: {
      $0.gameScoring.recordGoal = { command in
        expectNoDifference(command.teamID, UUID(2))
        expectNoDifference(command.scoringContext, .livePeriod(number: 1))
        return GameScoreSnapshot(canUndo: true, centrePassTeamID: UUID(2), teamBScore: 1)
      }
      $0.gameTimer.refreshActivity = { _ in }
    }
    await store.send(.goalButtonTapped(UUID(2)))
    await store.receive {
      if case .goalResponse(.success) = $0 { true } else { false }
    } assert: {
      $0.canUndo = true
      $0.centrePassTeamID = UUID(2)
      $0.teamBScore = 1
      $0.goalFeedbackTrigger = 1
    }
    await store.finish()
  }
}
