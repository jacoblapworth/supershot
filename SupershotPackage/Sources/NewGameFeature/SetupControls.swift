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

package struct SetupCentrePassView: View {
  @Binding package var firstCentrePass: NewGameFeature.TeamSide
  package var leftTeamName: String
  package var rightTeamName: String

  package var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("First centre pass", selection: $firstCentrePass) {
        Text(leftTeamName)
          .tag(NewGameFeature.TeamSide.teamA)
        Text(rightTeamName)
          .tag(NewGameFeature.TeamSide.teamB)
      }
      .pickerStyle(.segmented)
    }
    .setupCardStyle()
  }

  package init(
    firstCentrePass: Binding<NewGameFeature.TeamSide>, leftTeamName: String, rightTeamName: String
  ) {
    _firstCentrePass = firstCentrePass
    self.leftTeamName = leftTeamName
    self.rightTeamName = rightTeamName
  }
}

package struct SetupStartBar: View {
  package var canStartGame: Bool
  package var configurationSummary: String
  package var errorMessage: String?
  package var isSaving: Bool
  package var startGameTapped: () -> Void
  package var isScheduled = false
  package var startNowTapped: () -> Void = {}
  package var retryTapped: () -> Void = {}
  package var canRetry = false

  package var body: some View {
    VStack(spacing: 10) {
      Text(configurationSummary)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
        if canRetry {
          Button("Retry", action: retryTapped).disabled(isSaving)
        }
      }

      Button {
        startGameTapped()
      } label: {
        if isSaving {
          ProgressView()
            .frame(maxWidth: .infinity)
        } else {
          Text(isScheduled ? "Save game" : "Start game")
            .padding(8)
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.glassProminent)
      .buttonSizing(.flexible)
      .disabled(!canStartGame)
      if isScheduled {
        Button {
          startNowTapped()
        } label: {
          Text("Start now")
            .padding(8)
        }

        .disabled(!canStartGame)
        .buttonSizing(.flexible)
        .buttonStyle(.glass)
      }
    }
    .setupCardStyle()
  }

  package init(
    canStartGame: Bool, configurationSummary: String, errorMessage: String? = nil, isSaving: Bool,
    startGameTapped: @escaping () -> Void,
    isScheduled: Bool = false, startNowTapped: @escaping () -> Void = {},
    retryTapped: @escaping () -> Void = {}, canRetry: Bool = false
  ) {
    self.canStartGame = canStartGame
    self.configurationSummary = configurationSummary
    self.errorMessage = errorMessage
    self.isSaving = isSaving
    self.startGameTapped = startGameTapped
    self.isScheduled = isScheduled
    self.startNowTapped = startNowTapped
    self.retryTapped = retryTapped
    self.canRetry = canRetry
  }
}

#Preview("Centre pass") {
  SetupCentrePassView(
    firstCentrePass: .constant(.teamA),
    leftTeamName: "Ravens",
    rightTeamName: "Swifts"
  )
  .padding()
}

#Preview("Start game") {
  SetupStartBar(
    canStartGame: true,
    configurationSummary: "8 min quarters · 1 min breaks",
    errorMessage: nil,
    isSaving: false,
    startGameTapped: {}
  )
}

#Preview("Start game error") {
  SetupStartBar(
    canStartGame: false,
    configurationSummary: "8 min quarters · 1 min breaks",
    errorMessage: "Team names must be unique.",
    isSaving: false,
    startGameTapped: {}
  )
}

#Preview("Saving game") {
  SetupStartBar(
    canStartGame: false,
    configurationSummary: "8 min quarters · 1 min breaks",
    errorMessage: nil,
    isSaving: true,
    startGameTapped: {}
  )
}

package struct SetupGameDetailsView: View {
  @Bindable var store: StoreOf<NewGameFeature>

  package var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Toggle(
        "Scheduled date and time",
        isOn: Binding(
          get: { store.scheduledAt != nil },
          set: { store.send(.scheduleToggleChanged($0)) }
        )
      )
      Divider()
      if store.scheduledAt != nil {
        DatePicker(
          "Scheduled",
          selection: Binding(
            get: { store.scheduledAt ?? store.createdAt },
            set: { store.scheduledAt = $0 }
          )
        )
      } else {
        Text("Now").foregroundStyle(.secondary)
      }
      Divider()
      LabeledContent {
        TextField("Optional", text: $store.court)
          .keyboardType(.numbersAndPunctuation)
          .textFieldStyle(.plain)
          .accessibilityLabel("Court")
          .accessibilityIdentifier("gameSetup.court")
      } label: {
        Label("Court", systemImage: "sportscourt")
      }
      Divider()
      LabeledContent {
        TextField("Optional", text: $store.division)
          .keyboardType(.numbersAndPunctuation)
          .textFieldStyle(.plain)
          .accessibilityLabel("Division")
          .accessibilityIdentifier("gameSetup.division")
      } label: {
        Label("Division", systemImage: "chart.bar.fill")
      }
    }
    .setupCardStyle()
  }
}
