//
//  TeamCard.swift
//  Supershot
//
//  Created by J on 14/08/2026.
//


import ComposableArchitecture
import SwiftUI

struct TeamCard: View {
  var action: () -> Void
  var team: Team?

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        if let team {
          Circle()
            .fill(team.color)
            .frame(width: 30, height: 30)
            .overlay {
              Circle().stroke(.white.opacity(0.8), lineWidth: 2)
            }
            .accessibilityHidden(true)

          Text(team.name)
            .font(.headline)
            .lineLimit(2)
            .multilineTextAlignment(.center)


        } else {
          VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus").font(.title)
            Text("Team").font(.headline)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 150)
      .padding(10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(team.map { "Configure \($0.name)" } ?? "Select team")
  }
}

#Preview("Selected") {
  TeamCard(action: {}, team: .previewFoxes)
}

#Preview("Empty") {
  TeamCard(action: {})
}

