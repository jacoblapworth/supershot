//
//  TeamCard.swift
//  Supershot
//
//  Created by J on 14/08/2026.
//


import ComposableArchitecture
import SwiftUI

private struct TeamCard: View {
  var action: () -> Void
  var team: Team?

  var body: some View {
    VStack(spacing: 10) {
      if let team {
        Circle()
          .fill(Color(teamHex: team.colorHex))
          .frame(width: 30, height: 30)
          .overlay {
            Circle().stroke(.white.opacity(0.8), lineWidth: 2)
          }
          .accessibilityHidden(true)

        Text(team.name)
          .font(.headline)
          .lineLimit(2)
          .multilineTextAlignment(.center)

        HStack(spacing: 8) {
          Button("Change", action: action)
          .font(.caption)
          .buttonStyle(.bordered)
        }
      } else {
        Button(action: action) {
          VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
              .font(.title)
            Text("Team")
              .font(.headline)
            Text("Tap to choose")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 150)
    .padding(10)
    .background(
      Color(teamHex: team?.colorHex ?? TeamColorPalette.blue)
        .opacity(0.09),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          Color.secondary.opacity(0.25),
          lineWidth: 1
        )
    }
  }
}