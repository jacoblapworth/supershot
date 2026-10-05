//
//  TeamCard.swift
//  Supershot
//
//  Created by J on 14/08/2026.
//


import SwiftUI

struct TeamCard: View {
  var action: () -> Void
  var team: Team?

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 16) {
        if let team {
          Circle()
            .fill(team.color)
            .frame(width: 28, height: 28)
            .overlay {
              Circle().stroke(team.color.opacity(0.12), lineWidth: 2)
            }
            .accessibilityHidden(true)

          Spacer(minLength: 16)
          VStack(alignment: .leading, spacing: 5) {
            Text(team.name)
              .font(.headline)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
            Text("Configure team")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } else {
          VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus").font(.title)
            Text("Select team").font(.headline)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
      .background {
        TeamCardBackground(color: team?.color)
      }
      .clipShape(.rect(cornerRadius: 21))
      .overlay {
        RoundedRectangle(cornerRadius: 21)
          .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
      }
      .contentShape(.rect(cornerRadius: 21))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(team.map { "Configure \($0.name)" } ?? "Select team")
  }
}

private struct TeamCardBackground: View {
  var color: Color?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Color(uiColor: .secondarySystemBackground)
      .overlay {
        if let color {
          TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion || scenePhase != .active)) { context in
            let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate / 12
            GeometryReader { geometry in
              let size = geometry.size
              ZStack {
                Ellipse()
                  .fill(color.opacity(0.65))
                  .frame(width: size.width * 1.5, height: size.height * 0.95)
                  .blur(radius: 30)
                  .offset(x: size.width * (0.35 + 0.08 * sin(phase)), y: -size.height * 0.42)
                Ellipse()
                  .fill(color.opacity(0.28))
                  .frame(width: size.width, height: size.height * 0.7)
                  .blur(radius: 25)
                  .offset(x: -size.width * 0.45, y: size.height * (0.1 + 0.06 * cos(phase)))
              }
              .frame(width: size.width, height: size.height)
            }
          }
        }
      }
      .accessibilityHidden(true)
      .allowsHitTesting(false)
  }
}

#Preview("Selected") {
  TeamCard(action: {}, team: .previewFoxes)
}

#Preview("Empty") {
  TeamCard(action: {})
}

#Preview("Selected · Dark") {
  TeamCard(action: {}, team: .previewFoxes)
    .preferredColorScheme(.dark)
}
