import AlarmClient
import AppSettings
import Database
import GameAnalysis
import GameCore
import GameServices
import PermissionsFeature
import PreviewSupport
import SharedModels
import SoundEffectsClient
import Styleguide
import SubscriptionClient
import SwiftUI
import WidgetSupport

//
//  LastCentrePassBanner.swift
//  Supershot
//
//  Created by J on 03/08/2026.
//

package struct LastCentrePassBanner: View {
  package var centrePassTeam: ScoringFeature.Team
  package var isTransitioningPeriod: Bool
  package var period: Int
  package var lastCentrePassNotTakenTapped: () -> Void
  package var lastCentrePassTakenTapped: () -> Void

  package var body: some View {
    VStack(alignment: .center, spacing: 14) {
      Text("Quarter \(period)")
        .font(.headline)

      HStack(spacing: 8) {
        Circle()
          .fill(centrePassTeam.bibColor)
          .frame(width: 12, height: 12)
          .accessibilityHidden(true)
        Text("Did **\(centrePassTeam.name)** take the last centre pass?")
      }

      HStack(spacing: 10) {
        Button("No, not taken", action: lastCentrePassNotTakenTapped)
          .buttonSizing(.flexible)
          .buttonStyle(.bordered)
        Button("Yes, pass taken", action: lastCentrePassTakenTapped)
          .buttonSizing(.flexible)
          .buttonStyle(.borderedProminent)
      }
      .fontWeight(.medium)
      .controlSize(.large)
      .disabled(isTransitioningPeriod)

      if isTransitioningPeriod {
        ProgressView("Saving quarter…")
          .font(.caption)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: RoundedRectangle(cornerRadius: 24))
    .accessibilityElement(children: .contain)
  }

  package init(
    centrePassTeam: ScoringFeature.Team, isTransitioningPeriod: Bool, period: Int,
    lastCentrePassNotTakenTapped: @escaping () -> Void,
    lastCentrePassTakenTapped: @escaping () -> Void
  ) {
    self.centrePassTeam = centrePassTeam
    self.isTransitioningPeriod = isTransitioningPeriod
    self.period = period
    self.lastCentrePassNotTakenTapped = lastCentrePassNotTakenTapped
    self.lastCentrePassTakenTapped = lastCentrePassTakenTapped
  }
}

#Preview("Last centre pass") {
  LastCentrePassBanner(
    centrePassTeam: .previewSwifts,
    isTransitioningPeriod: false,
    period: 2,
    lastCentrePassNotTakenTapped: {},
    lastCentrePassTakenTapped: {}
  )
  .padding()
}

#Preview("Saving quarter") {
  LastCentrePassBanner(
    centrePassTeam: .previewSwifts,
    isTransitioningPeriod: true,
    period: 2,
    lastCentrePassNotTakenTapped: {},
    lastCentrePassTakenTapped: {}
  )
  .padding()
}
