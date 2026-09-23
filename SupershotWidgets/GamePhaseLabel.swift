//
//  GamePhaseLabel.swift
//  SupershotWidgets
//
//  Created by J on 16/09/2026.
//

import SwiftUI

struct GamePhaseLabel: View {
  enum Size {
    case short
    case long
  }
  
  var phase: GamePhase
  var size: Size = .long
  
  private var label: String {
    switch phase {
    case .period(let number, _):
      switch size {
      case .short:
        return "Q\(number)"
      case .long:
        return "Quarter \(number)"
      }
    case .breakTime:
      switch size {
      case .short:
        return "B"
      case .long:
        return "Break"
      }
    }
  }
  
  var body: some View {
    Text(label)
  }
}

#Preview {
  GamePhaseLabel(phase: .period(number: 1, durationSeconds: 60))
}
