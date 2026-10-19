import AppSettings
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
      Label("First centre pass", systemImage: "arrow.left.arrow.right")
        .font(.headline)

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
    self._firstCentrePass = firstCentrePass
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
      }

      Button {
        startGameTapped()
      } label: {
        if isSaving {
          ProgressView()
            .frame(maxWidth: .infinity)
        } else {
          Text("Continue")
            .padding(8)
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.glassProminent)
      .disabled(!canStartGame)
    }
    .padding()
    .background(.bar)
  }

  package init(
    canStartGame: Bool, configurationSummary: String, errorMessage: String? = nil, isSaving: Bool,
    startGameTapped: @escaping () -> Void
  ) {
    self.canStartGame = canStartGame
    self.configurationSummary = configurationSummary
    self.errorMessage = errorMessage
    self.isSaving = isSaving
    self.startGameTapped = startGameTapped
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
