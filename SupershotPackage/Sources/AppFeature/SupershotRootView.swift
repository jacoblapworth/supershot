import ComposableArchitecture
import SwiftUI

/// Retain each window’s store when shared preferences change during onboarding.
public struct SupershotRootView: View {
  public init() {}

  @State private var store = Store(initialState: Self.initialState()) { AppFeature() }

  private static func initialState() -> AppFeature.State {
    #if DEBUG
      GoalDeletionLaunchScenario.initialState()
    #else
      AppFeature.State()
    #endif
  }

  public var body: some View {
    AppView(store: store)
  }
}
