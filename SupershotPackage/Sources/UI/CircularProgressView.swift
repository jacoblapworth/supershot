import SwiftUI

//
//  CircularProgressView.swift
//  Supershot
//
//  Created by J on 04/08/2026.
//

package struct CircularProgressView: View {
  package var value: Double
  package var total: Double

  private var lineWidth: CGFloat = 6

  package var body: some View {
    ZStack {
      Circle()
        .stroke(lineWidth: lineWidth)
        .opacity(0.1)
      Circle()
        .trim(from: 0, to: min(value, total) / total)
        .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        .rotationEffect(Angle(degrees: 270))
        .animation(.linear, value: value)
    }
  }

  package init(value: Double, total: Double) {
    self.value = value
    self.total = total
  }
}

#Preview {
  CircularProgressView(value: 20, total: 120)
}
