import SwiftUI

struct SetupCentrePassView: View {
  @Binding var firstCentrePass: NewGameFeature.TeamSide?
  var leftTeamName: String
  var rightTeamName: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("First centre pass", systemImage: "arrow.left.arrow.right")
        .font(.headline)

      Picker("First centre pass", selection: $firstCentrePass) {
        Text(leftTeamName)
          .tag(NewGameFeature.TeamSide?.some(.teamA))
        Text(rightTeamName)
          .tag(NewGameFeature.TeamSide?.some(.teamB))
      }
      .pickerStyle(.segmented)
    }
    .setupCardStyle()
  }
}

struct SetupStartBar: View {
  var canStartGame: Bool
  var configurationSummary: String
  var errorMessage: String?
  var isSaving: Bool
  var startGameTapped: () -> Void

  var body: some View {
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
          Label("Start game", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canStartGame)
    }
    .padding()
    .background(.bar)
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
    configurationSummary: "15 min quarters · 4 min breaks",
    errorMessage: nil,
    isSaving: false,
    startGameTapped: {}
  )
}

#Preview("Start game error") {
  SetupStartBar(
    canStartGame: false,
    configurationSummary: "15 min quarters · 4 min breaks",
    errorMessage: "Team names must be unique.",
    isSaving: false,
    startGameTapped: {}
  )
}

#Preview("Saving game") {
  SetupStartBar(
    canStartGame: false,
    configurationSummary: "15 min quarters · 4 min breaks",
    errorMessage: nil,
    isSaving: true,
    startGameTapped: {}
  )
}
