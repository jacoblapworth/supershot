import ComposableArchitecture
import SwiftUI

/// Retain each window’s store when shared preferences change during onboarding.
public struct SupershotRootView: View {
  public init() {}

  @State private var store = Store(initialState: AppFeature.State()) {
    AppFeature()
  }

  public var body: some View {
    AppView(store: store)
  }
}
