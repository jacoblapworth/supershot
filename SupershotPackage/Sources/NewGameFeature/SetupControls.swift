import AppSettings
import AppUI
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
import SubscriptionClient
import SwiftUI
import TeamEditingFeature
import UI

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
    canPrepareScoring: Bool,
    configurationSummary: String,
    errorMessage: String? = nil,
    isSaving: Bool,
    prepareScoringTapped: @escaping () -> Void,
    isScheduled: Bool = false,
    prepareScoringNowTapped: @escaping () -> Void = {},
    retryTapped: @escaping () -> Void = {},
    canRetry: Bool = false
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
