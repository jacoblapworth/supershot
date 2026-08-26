//
//  TeamLabelView.swift
//  Supershot
//
//  Created by J on 26/08/2026.
//

import SwiftUI

struct TeamLabelView: View {
  var name: String
  var color: Color
  var alignment: HorizontalAlignment = .leading
  
  private var avatar: some View {
    AvatarView(label: name)
      .controlSize(.mini)
  }
  
  var body: some View {
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
}

#Preview {
  TeamLabelView(
    name: "Team One",
    color: .blue,
  )
}
