@testable import AppFeature
import ComposableArchitecture
import Dependencies
import Foundation
import GamesFeature
import NewGameFeature
import PermissionsFeature
import Testing

extension SupershotTestSuite {
  @MainActor
  struct GamesWidgetNavigationTests {
    @Test(arguments: ["supershot", "supershot-dev"])
    func emptyWidgetOpensNewGame(scheme: String) async throws {
      let store = TestStore(initialState: AppFeature.State()) { AppFeature() }
        withDependencies: { $0.defaultAppStorage.set(true, forKey: "hasCompletedWelcome") }
      store.exhaustivity = .off(showSkippedAssertions: false)
      await store.send(.deepLinkOpened(try #require(URL(string: "\(scheme)://new-game"))))
      await store.receive(\.games.newGameButtonTapped)
      #expect(store.state.selectedTab == .games)
      #expect(store.state.games.newGame != nil)
    }

    @Test func emptyWidgetDefersSetupUntilWelcomeCompletes() async throws {
      let store = TestStore(initialState: AppFeature.State()) { AppFeature() }
        withDependencies: { $0.defaultAppStorage.set(false, forKey: "hasCompletedWelcome") }
      store.exhaustivity = .off(showSkippedAssertions: false)
      let url = try #require(URL(string: "supershot://new-game"))
      await store.send(.deepLinkOpened(url))
      #expect(store.state.pendingDeepLink == url)
      #expect(store.state.games.newGame == nil)
      await store.send(.destination(.presented(.welcome(.delegate(.completed)))))
      await store.receive(\.deepLinkOpened)
      await store.receive(\.games.newGameButtonTapped)
      #expect(store.state.pendingDeepLink == nil)
      #expect(store.state.games.newGame != nil)
    }
  }
}
