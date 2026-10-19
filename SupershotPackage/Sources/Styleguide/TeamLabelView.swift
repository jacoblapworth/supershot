import GameCore
import SharedModels
import SwiftUI
import WidgetSupport

//
//  TeamLabelView.swift
//  Supershot
//
//  Created by J on 26/08/2026.
//

package struct TeamLabelView: View {
  package var name: String
  package var color: Color
  package var alignment: HorizontalAlignment = .leading

  private var avatar: some View {
    AvatarView(label: name, color: color)
      .controlSize(.mini)
  }

  package var body: some View {
    HStack(alignment: .center, spacing: 6) {
      if alignment == .leading { avatar }
      Text(name)
        .font(.caption)
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
      if alignment == .trailing { avatar }
    }
    .controlSize(.small)
  }

  package init(name: String, color: Color, alignment: HorizontalAlignment = .leading) {
    self.name = name
    self.color = color
    self.alignment = alignment
  }
}

#Preview {
  TeamLabelView(
    name: "Team One",
    color: .blue,
  )
}
