import ComposableArchitecture
import Foundation
import SQLiteData
import SwiftUI
import Testing

@testable import Supershot

extension SupershotTestSuite {
  @MainActor
  @Suite struct SetupEditorFeatureTests {
    @Test func selectedTeamOpensConfigurationAndPreservesCentrePass() async {
      var state = NewGameFeature.State.previewReady
      state.firstCentrePass = .teamB
      let store = TestStore(initialState: state) { NewGameFeature() }
      await store.send(.selectTeamButtonTapped(.teamA)) {
        $0.destination = .teamConfiguration(
          NewGameTeamConfiguration.State(
            configuration: SetupTeamFeature.State(
              team: state.leftTeam.team!,
              excluding: [state.rightTeam.team!.id]
            ),
            side: .teamA
          )
        )
      }
      #expect(store.state.firstCentrePass == .teamB)
    }

    @Test func pickerDismissalOpensConfiguration() async {
      var state = NewGameFeature.State()
      state.leftTeam.team = .previewFoxes
      state.pendingTeamConfiguration = NewGameTeamConfiguration.State(
        configuration: SetupTeamFeature.State(team: .previewFoxes),
        side: .teamA
      )
      let store = TestStore(initialState: state) { NewGameFeature() }
      await store.send(.destinationDidDismiss) {
        $0.destination = .teamConfiguration(
          NewGameTeamConfiguration.State(
            configuration: SetupTeamFeature.State(team: .previewFoxes),
            side: .teamA
          )
        )
        $0.pendingTeamConfiguration = nil
      }
    }

    @Test func timingDraftIsIsolatedUntilDone() async {
      let store = TestStore(initialState: NewGameFeature.State()) { NewGameFeature() }
      await store.send(.editTimingButtonTapped) {
        $0.destination = .timingEditor(SetupTimingFeature.State(timing: $0.timing))
      }
      await store.send(.destination(.presented(.timingEditor(.periodPresetButtonTapped(900))))) {
        var timing = $0.timing
        timing.periodDuration = .init(totalSeconds: 900)
        $0.destination = .timingEditor(SetupTimingFeature.State(timing: timing))
      }
      #expect(store.state.periodDuration.totalSeconds == 480)
      await store.send(.destination(.presented(.timingEditor(.doneButtonTapped))))
      await store.receive {
        guard case .destination(.presented(.timingEditor(.delegate(.committed)))) = $0 else {
          return false
        }
        return true
      } assert: {
        $0.periodDuration = .init(totalSeconds: 900)
        $0.destination = nil
      }
    }

    @Test func cancellingTimingDiscardsDraft() async {
      var state = NewGameFeature.State()
      var draft = state.timing
      draft.periodDuration = .init(totalSeconds: 900)
      state.destination = .timingEditor(SetupTimingFeature.State(timing: draft))
      let store = TestStore(initialState: state) { NewGameFeature() }
      await store.send(.destination(.presented(.timingEditor(.cancelButtonTapped))))
      await store.receive {
        guard case .destination(.presented(.timingEditor(.delegate(.cancelled)))) = $0 else {
          return false
        }
        return true
      } assert: {
        $0.destination = nil
      }
      #expect(store.state.periodDuration.totalSeconds == 480)
    }

    @Test func swipingTimingSheetDiscardsDraft() async {
      var state = NewGameFeature.State()
      var draft = state.timing
      draft.periodDuration = .init(totalSeconds: 900)
      state.destination = .timingEditor(SetupTimingFeature.State(timing: draft))
      let store = TestStore(initialState: state) { NewGameFeature() }
      await store.send(.destination(.dismiss)) { $0.destination = nil }
      #expect(store.state.periodDuration.totalSeconds == 480)
    }

    @Test func pendingColourWriteBlocksDoneAndReplacement() async {
      var state = SetupTeamFeature.State(team: .previewRavens)
      state.isSaving = true
      let store = TestStore(initialState: state) { SetupTeamFeature() }
      await store.send(.doneButtonTapped)
      await store.send(.changeTeamButtonTapped)
      #expect(store.state.picker == nil)
    }

    @Test func invalidTimingCannotCommit() async {
      var timing = SetupTiming()
      timing.periodDuration = .init(totalSeconds: 0)
      let store = TestStore(initialState: SetupTimingFeature.State(timing: timing)) { SetupTimingFeature() }
      await store.send(.doneButtonTapped)
      #expect(!store.state.timing.isValid)
    }

    @Test func swappingKeepsFirstPassWithTheSameTeam() async {
      let state = NewGameFeature.State.previewReady
      let store = TestStore(initialState: state) { NewGameFeature() }
      await store.send(.swapTeamsButtonTapped) {
        $0.leftTeam = state.rightTeam
        $0.rightTeam = state.leftTeam
        $0.firstCentrePass = .teamB
      }
      #expect(store.state.canStartGame)
    }

    @Test func replacementPickerExcludesOpponentAndCancelKeepsTeam() async {
      let state = SetupTeamFeature.State(team: .previewRavens, excluding: [Team.previewSwifts.id])
      let store = TestStore(initialState: state) { SetupTeamFeature() }
      await store.send(.changeTeamButtonTapped) {
        $0.picker = TeamPickerFeature.State(excluding: [Team.previewSwifts.id])
      }
      await store.send(.picker(.presented(.delegate(.cancelled)))) { $0.picker = nil }
      #expect(store.state.previewTeam == .previewRavens)
      await store.send(.changeTeamButtonTapped) {
        $0.picker = TeamPickerFeature.State(excluding: [Team.previewSwifts.id])
      }
      await store.send(.picker(.presented(.delegate(.teamSelected(.previewFoxes))))) {
        $0.savedTeam = .previewFoxes
        $0.draft = Team.Draft(Team.previewFoxes)
        $0.picker = nil
      }
      await store.receive(\.delegate.teamUpdated)
    }

    @Test func customizedBreaksHaveLabelledSummaryAndCanBeUnified() async {
      let timing = NewGameFeature.State.previewCustomTiming.timing
      let store = TestStore(initialState: SetupTimingFeature.State(timing: timing)) { SetupTimingFeature() }
      #expect(store.state.timing.summary.contains("Half time 10:00"))
      await store.send(.useFirstBreakForAllButtonTapped) {
        $0.timing.customizesBreaks = false
        $0.timing.halfTimeDuration = timing.firstBreakDuration
        $0.timing.secondBreakDuration = timing.firstBreakDuration
      }
      #expect(store.state.timing.summary == "4 × 8:00 · 2:00 breaks")
    }

    @Test func colourWritesPreserveNameAndPersistLatestSelection() async throws {
      let team = Team(id: UUID(1), name: "Ravens", colorHex: ColorPalette.blue.hex())
      let opponent = Team(id: UUID(2), name: "Swifts", colorHex: ColorPalette.red.hex())
      let pastGame = Game(id: UUID(3), startedAt: Date(timeIntervalSince1970: 100), teamAID: team.id, teamABibColorHex: team.colorHex, teamBID: opponent.id)
      let store = TestStore(initialState: SetupTeamFeature.State(team: team)) { SetupTeamFeature() }
        withDependencies: {
          try! $0.bootstrapDatabase()
          try! clearDatabase($0.defaultDatabase)
          try! $0.defaultDatabase.write { db in
            try Team.insert { team; opponent }.execute(db)
            try Game.insert { pastGame }.execute(db)
          }
        }
      store.exhaustivity = .off
      await store.send(.colorChanged(ColorPalette.red))
      #expect(store.state.previewTeam.colorHex == ColorPalette.red.hex())
      await store.send(.colorChanged(ColorPalette.green))
      #expect(store.state.previewTeam.colorHex == ColorPalette.green.hex())
      await store.receive(\.saveResponse)
      if store.state.isSaving { await store.receive(\.saveResponse) }
      await store.finish()
      let saved = try await store.dependencies.defaultDatabase.read { db in try Team.find(team.id).fetchOne(db) }
      #expect(saved?.colorHex == ColorPalette.green.hex())
      #expect(saved?.name == "Ravens")
      let history = try await store.dependencies.defaultDatabase.read { db in try Game.find(pastGame.id).fetchOne(db) }
      #expect(history?.teamABibColorHex == team.colorHex)
      #expect(!store.state.isSaving)
    }

    @Test func failedColourWriteRollsBackAndCanRetry() async throws {
      let team = Team(id: UUID(1), name: "Missing", colorHex: ColorPalette.blue.hex())
      let store = TestStore(initialState: SetupTeamFeature.State(team: team)) { SetupTeamFeature() }
        withDependencies: {
          try! $0.bootstrapDatabase()
          try! clearDatabase($0.defaultDatabase)
        }
      store.exhaustivity = .off
      await store.send(.colorChanged(ColorPalette.red))
      await store.receive(\.saveResponse)
      await store.finish()
      #expect(store.state.previewTeam == team)
      #expect(store.state.failedColorHex == ColorPalette.red.hex())
      #expect(store.state.errorMessage != nil)
      try await store.dependencies.defaultDatabase.write { db in try Team.insert { team }.execute(db) }
      await store.send(.retryButtonTapped)
      await store.receive(\.colorChanged)
      await store.receive(\.saveResponse)
      await store.finish()
      #expect(store.state.previewTeam.colorHex == ColorPalette.red.hex())
      #expect(store.state.errorMessage == nil)
      let saved = try await store.dependencies.defaultDatabase.read { db in try Team.find(team.id).fetchOne(db) }
      #expect(saved?.colorHex == ColorPalette.red.hex())
    }
  }
}
