//
//  GameLocationSection.swift
//  SupershotPackage
//
//  Created by J on 11/11/2026.
//


import AppUI
import Database
import GameCore
import LocationClient
import PaywallFeature
import PreviewSupport
import SharedModels
import SwiftUI
import UI

package struct GameLocationSection: View {
  var location: GameLocation

  package var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      GameLocationMap(location: location)
      Label {
        if let pointOfInterestName = location.pointOfInterestName {
          Text(pointOfInterestName)
        } else {
          Text("Game location")
        }
      } icon: {
        Image(systemName: "mappin.and.ellipse")
      }
      .font(.subheadline)
      .padding()
    }
    
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}
