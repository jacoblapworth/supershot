import ComposableArchitecture
import SwiftUI

/// Retain each window’s store when shared preferences change during onboarding.
public struct SupershotRootView: View {
  public init() {}

  @State private var store = Store(initialState: Self.initialState()) {
    AppFeature()
  }

  private static func initialState() -> AppFeature.State {
    #if DEBUG
      if SettingsLaunchScenario.isRequested {
        return SettingsLaunchScenario.initialState()
      }
    #endif
    return AppFeature.State()
  }

  public var body: some View {
    AppView(store: store)
  }
}
