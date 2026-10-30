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
  package var canPrepareScoring: Bool
  package var configurationSummary: String
  package var errorMessage: String?
  package var isSaving: Bool
  package var prepareScoringTapped: () -> Void
  package var isScheduled = false
  package var prepareScoringNowTapped: () -> Void = {}
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
          Button("Retry", action: retryTapped)
            .buttonStyle(.borderless)
            .disabled(isSaving)
        }
      }

      Button {
        prepareScoringTapped()
      } label: {
        if isSaving {
          ProgressView()
            .frame(maxWidth: .infinity)
        } else {
          Text(isScheduled ? "Save game" : "Ready to score")
            .padding(8)
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.glassProminent)
      .buttonSizing(.flexible)
      .disabled(!canPrepareScoring)
      if isScheduled {
        Button {
          prepareScoringNowTapped()
        } label: {
          Text("Ready to score now")
            .padding(8)
        }

        .disabled(!canPrepareScoring)
        .buttonSizing(.flexible)
        .buttonStyle(.glass)
      }
    }
    .setupCardStyle()
  }

  package init(
    canPrepareScoring: Bool, configurationSummary: String, errorMessage: String? = nil, isSaving: Bool,
    prepareScoringTapped: @escaping () -> Void,
    isScheduled: Bool = false, prepareScoringNowTapped: @escaping () -> Void = {},
    retryTapped: @escaping () -> Void = {}, canRetry: Bool = false
  ) {
    self.canPrepareScoring = canPrepareScoring
    self.configurationSummary = configurationSummary
    self.errorMessage = errorMessage
    self.isSaving = isSaving
    self.prepareScoringTapped = prepareScoringTapped
    self.isScheduled = isScheduled
    self.prepareScoringNowTapped = prepareScoringNowTapped
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
    canPrepareScoring: true,
    configurationSummary: "8 min quarters · 1 min breaks",
    errorMessage: nil,
    isSaving: false,
    prepareScoringTapped: {}
  )
}

#Preview("Start game error") {
  SetupStartBar(
    canPrepareScoring: false,
    configurationSummary: "8 min quarters · 1 min breaks",
    errorMessage: "Team names must be unique.",
    isSaving: false,
    prepareScoringTapped: {}
  )
}

#Preview("Saving game") {
  SetupStartBar(
    canPrepareScoring: false,
    configurationSummary: "8 min quarters · 1 min breaks",
    errorMessage: nil,
    isSaving: true,
    prepareScoringTapped: {}
  )
}

package struct SetupGameDetailsView: View {
  @Bindable var store: StoreOf<NewGameFeature>

  package var body: some View {
    TimelineView(.everyMinute) { context in
      HStack {
        DatePicker(
          selection: Binding(
            get: { store.scheduledAt ?? context.date },
            set: { store.scheduledAt = $0 }
          )
        ) {
          Label("Start", systemImage: "calendar")
        }
        .datePickerStyle(.compact)
        .accessibilityIdentifier("gameSetup.dateTime")

        if store.scheduledAt != nil {
          Button {
            store.scheduledAt = nil
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Clear date and time")
          .accessibilityHint("Use the current date and time")
          .accessibilityIdentifier("gameSetup.clearDateTime")
        }
      }
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
      Label("Division", systemImage: "chart.bar.fill")
    }
  }
}
