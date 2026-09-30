//
//  CircularProgressView.swift
//  Supershot
//
//  Created by J on 04/08/2026.
//

import SwiftUI

struct CircularProgressView: View {
  var value: Double
  var total: Double
  
  private var lineWidth: CGFloat = 6
  
  var body: some View {
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
}

#Preview {
  CircularProgressView(value: 20, total: 120)
}
