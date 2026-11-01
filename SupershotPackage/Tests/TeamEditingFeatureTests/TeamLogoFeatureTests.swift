import ComposableArchitecture
import CustomDump
@testable import Database
import Dependencies
import Foundation
import GameCore
import SQLiteData
import SwiftUI
@testable import TeamEditingFeature
import TeamLogoClient
import Testing
import TestSupport
import UI

extension SupershotTestSuite {
  @MainActor
  struct TeamLogoFeatureTests {
    @Test
    func importAutomaticallySelectsColourAndAllowsOverride() async {
      let logo = PreparedTeamLogo(data: Data([1]), colors: ["#0066CC", "#FFFFFF"])
      let store = TestStore(initialState: TeamEditorFeature.State(team: Team(id: UUID(10), name: "Ravens"))) {
        TeamEditorFeature()
      } withDependencies: {
        $0.uuid = .incrementing
        $0.teamLogoClient.prepare = { _ in logo }
      }
      await store.send(.logoSelected(.data(Data([0])))) {
        $0.logoRequestID = UUID(0)
        $0.isProcessingLogo = true
        $0.focus = nil
      }
      await store.receive(\.logoResponse) {
        $0.logoRequestID = nil
        $0.isProcessingLogo = false
        $0.logoData = logo.data
        $0.logoColors = logo.colors
        $0.color = Color(hex: "#0066CC")
      }
      #expect(store.state.canSave)
      await store.send(.binding(.allCasePaths.color.embed(Color(hex: "#FF0000")))) {
        $0.color = Color(hex: "#FF0000")
      }
      await store.send(.removeLogoButtonTapped) {
        $0.logoData = nil
        $0.logoColors = []
      }
      expectNoDifference(store.state.color.hex(), "#FF0000")
    }

    @Test
    func reopeningLogoRebuildsPaletteWithoutChangingColour() async {
      let team = Team(id: UUID(10), name: "Ravens", colorHex: "#FF0000", logoData: Data([1]))
      let store = TestStore(initialState: TeamEditorFeature.State(team: team)) {
        TeamEditorFeature()
      } withDependencies: {
        $0.uuid = .incrementing
        $0.teamLogoClient.colors = { _ in ["#0066CC"] }
      }
      await store.send(.task) { $0.logoRequestID = UUID(0) }
      await store.receive(\.logoResponse) {
        $0.logoRequestID = nil
        $0.logoColors = ["#0066CC"]
      }
      expectNoDifference(store.state.color.hex(), "#FF0000")
      #expect(!store.state.canSave)
    }

    @Test
    func failedImportPreservesDraftAndCanRetry() async {
      let team = Team(id: UUID(10), name: "Ravens", colorHex: "#FF0000", logoData: Data([1]))
      let store = TestStore(initialState: TeamEditorFeature.State(team: team)) {
        TeamEditorFeature()
      } withDependencies: { $0.uuid = .incrementing }
      await store.send(.logoSelected(.data(Data()))) {
        $0.logoRequestID = UUID(0)
        $0.isProcessingLogo = true
        $0.focus = nil
      }
      #expect(!store.state.canSave)
      await store.receive(\.logoResponse) {
        $0.logoRequestID = nil
        $0.isProcessingLogo = false
        $0.errorMessage = "Couldn’t open this logo. Choose a PNG, JPEG, or HEIC image and try again."
      }
      expectNoDifference(store.state.logoData, team.logoData)
      expectNoDifference(store.state.color.hex(), team.colorHex)
      store.dependencies.teamLogoClient.prepare = { _ in PreparedTeamLogo(data: Data([2]), colors: []) }
      await store.send(.logoSelected(.data(Data([2])))) {
        $0.logoRequestID = UUID(1)
        $0.isProcessingLogo = true
        $0.errorMessage = nil
      }
      await store.receive(\.logoResponse) {
        $0.logoRequestID = nil
        $0.isProcessingLogo = false
        $0.logoData = Data([2])
      }
      expectNoDifference(store.state.color.hex(), team.colorHex)
    }

    @Test(arguments: [false, true])
    func removeOrCancelIgnoresLateResponses(cancel: Bool) async {
      let team = Team(id: UUID(10), name: "Ravens", logoData: Data([1]))
      var state = TeamEditorFeature.State(team: team)
      state.logoRequestID = UUID(20)
      state.isProcessingLogo = true
      let store = TestStore(initialState: state) { TeamEditorFeature() }
      if cancel {
        await store.send(.cancelButtonTapped) {
          $0.logoRequestID = nil
          $0.isProcessingLogo = false
        }
        await store.receive(\.delegate, .cancelled)
      } else {
        await store.send(.removeLogoButtonTapped) {
          $0.logoData = nil
          $0.logoRequestID = nil
          $0.isProcessingLogo = false
        }
      }
      await store.send(.logoResponse(UUID(20), .success(PreparedTeamLogo(data: Data([9]), colors: ["#FF0000"]))))
    }

    @Test
    func supersededResponseCannotReplaceNewerLogo() async {
      var state = TeamEditorFeature.State()
      state.logoRequestID = UUID(21)
      state.isProcessingLogo = true
      let store = TestStore(initialState: state) { TeamEditorFeature() }
      await store.send(.logoResponse(UUID(20), .success(PreparedTeamLogo(data: Data([9]), colors: ["#FF0000"]))))
      await store.send(.logoResponse(UUID(21), .success(PreparedTeamLogo(data: Data([2]), colors: [])))) {
        $0.logoRequestID = nil
        $0.isProcessingLogo = false
        $0.logoData = Data([2])
      }
    }

    @Test(arguments: [Data([2]), nil] as [Data?])
    func savesLogoOnlyChangesAndRemoval(logo: Data?) async throws {
      let team = Team(id: UUID(10), name: "Ravens", logoData: Data([1]))
      var state = TeamEditorFeature.State(team: team)
      state.logoData = logo
      let store = TestStore(initialState: state) { TeamEditorFeature() } withDependencies: {
        try! $0.defaultDatabase.write { db in try Team.insert { team }.execute(db) }
      }
      #expect(store.state.canSave)
      await store.send(.saveButtonTapped) { $0.isSaving = true }
      await store.receive(\.saveResponse) { $0.isSaving = false }
      var expected = team
      expected.logoData = logo
      await store.receive(\.delegate)
      let saved = try await store.dependencies.defaultDatabase.read { db in try Team.find(team.id).fetchOne(db) }
      expectNoDifference(saved, expected)
    }

    @Test
    func failedSaveKeepsLogoDraftForRetry() async {
      let team = Team(id: UUID(10), name: "Deleted", logoData: Data([1]))
      var state = TeamEditorFeature.State(team: team)
      state.logoData = Data([2])
      let store = TestStore(initialState: state) { TeamEditorFeature() }
      await store.send(.saveButtonTapped) { $0.isSaving = true }
      await store.receive(\.saveResponse) {
        $0.isSaving = false
        $0.errorMessage = "This team is no longer available."
      }
      expectNoDifference(store.state.logoData, Data([2]))
      #expect(store.state.canSave)
    }

    @Test
    func cancelDiscardsLogoAndColourEditsWithoutWriting() async throws {
      let team = Team(id: UUID(10), name: "Ravens", logoData: Data([1]))
      var state = TeamEditorFeature.State(team: team)
      state.logoData = Data([2])
      state.color = Color(hex: "#FF0000")
      let store = TestStore(initialState: state) { TeamEditorFeature() } withDependencies: {
        try! $0.defaultDatabase.write { db in try Team.insert { team }.execute(db) }
      }
      await store.send(.cancelButtonTapped)
      await store.receive(\.delegate, .cancelled)
      let saved = try await store.dependencies.defaultDatabase.read { db in try Team.find(team.id).fetchOne(db) }
      expectNoDifference(saved, team)
    }

    @Test
    func createsTeamWithLogo() async throws {
      var state = TeamEditorFeature.State()
      state.name = "New Ravens"
      state.logoData = Data([2])
      let store = TestStore(initialState: state) { TeamEditorFeature() } withDependencies: {
        $0.uuid = .incrementing
      }
      await store.send(.saveButtonTapped) { $0.isSaving = true }
      await store.receive(\.saveResponse) { $0.isSaving = false }
      await store.receive(\.delegate)
      let saved = try await store.dependencies.defaultDatabase.read { db in try Team.find(UUID(0)).fetchOne(db) }
      expectNoDifference(saved?.logoData, Data([2]))
      expectNoDifference(saved?.name, "New Ravens")
    }
  }
}
