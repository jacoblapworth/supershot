import AppSettings
import ComposableArchitecture
import Database
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

package struct GameDetailsView: View {
  @Bindable var store: StoreOf<NewGameFeature>
  @Dependency(\.date.now) var now

  package init(store: StoreOf<NewGameFeature>) {
    self.store = store
  }

  package var body: some View {
    Toggle(isOn: $store.scheduled) {
      Label("Scheduled", systemImage: "clock.arrow.trianglehead.clockwise.rotate.90.path.dotted")
    }

    if store.scheduled {
      DatePicker(
        selection: Binding(
          get: { store.scheduledAt ?? now },
          set: { store.scheduledAt = $0 }
        ),
        in: ClosedRange<Date>(uncheckedBounds: (lower: now, upper: .distantFuture)),
        displayedComponents: .date,
        label: {
          Label("Date", systemImage: "calendar")
        }
      )
      .frame(maxHeight: 24)

      DatePicker(
        selection: Binding(
          get: { store.scheduledAt ?? now },
          set: { store.scheduledAt = $0 }
        ),
        in: ClosedRange<Date>(uncheckedBounds: (lower: now, upper: .distantFuture)),
        displayedComponents: .hourAndMinute,
        label: {
          Label("Time", systemImage: "clock")
        }
      )
      .frame(maxHeight: 24)
    }

    LabeledContent {
      KeyboardSwitchingTextField(
        "Court",
        text: $store.court,
        keyboardTypes: [.alphabet, .numeric],
        initialKeyboardType: .numeric,
        accessibilityIdentifier: "gameSetup.court"
      )
    } label: {
      Label("Court", systemImage: "sportscourt")
    }

    LabeledContent {
      KeyboardSwitchingTextField(
        "Division",
        text: $store.division,
        keyboardTypes: [.alphabet, .numeric],
        initialKeyboardType: .numeric,
        accessibilityIdentifier: "gameSetup.division"
      )
    } label: {
      Label("Division", systemImage: "chart.bar")
    }
  }
}

#Preview {
  Form {
    GameDetailsView(store: Store(initialState: NewGameFeature.State()) {
      NewGameFeature()
    })
  }
}
