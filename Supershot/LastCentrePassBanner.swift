//
//  LastCentrePassBanner.swift
//  Supershot
//
//  Created by J on 03/08/2026.
//


import SwiftUI

struct LastCentrePassBanner: View {
  var centrePassTeam: ScoringFeature.Team
  var isTransitioningPeriod: Bool
  var period: Int
  var lastCentrePassNotTakenTapped: () -> Void
  var lastCentrePassTakenTapped: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Quarter \(period)")
        .font(.headline)

      HStack(spacing: 8) {
        Circle()
          .fill(Color(teamHex: centrePassTeam.bibColorHex))
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
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .contain)
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
