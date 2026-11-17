//
//  ScoreView.swift
//  SupershotPackage
//
//  Created by J on 17/11/2026.
//

import SwiftUI

struct ScoreView: View {
  
  enum Size {
    case small, standard, large
    
    var font: Font {
      switch self {
      case .small:
          .title
      case .standard, .large:
          .largeTitle
      }
    }
  }
  
  var value: Int
  var size: Size = .standard
  var dimmed: Bool = false
  
  var body: some View {
    Text(value, format: .number)
      .contentTransition(.numericText(value: Double(value)))
      .font(size.font)
      .fontWidth(.compressed)
      .fontWeight(.semibold)
      .opacity(dimmed ? 0.7 : 1)
      .fixedSize()
  }
}

#Preview {
  HStack {
    ScoreView(
      value: 24,
      size: .small,
      dimmed: false
    )
    ScoreView(
      value: 24,
      size: .standard,
      dimmed: false
    )
    ScoreView(
      value: 24,
      size: .large,
      dimmed: false
    )
    
  }
}
