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

package struct CentrePassView: View {
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
    firstCentrePass: Binding<NewGameFeature.TeamSide>,
    leftTeamName: String,
    rightTeamName: String
  ) {
    _firstCentrePass = firstCentrePass
    self.leftTeamName = leftTeamName
    self.rightTeamName = rightTeamName
  }
}

#Preview("Centre pass") {
  CentrePassView(
    firstCentrePass: .constant(.teamA),
    leftTeamName: "Ravens",
    rightTeamName: "Swifts"
  )
  .padding()
}
