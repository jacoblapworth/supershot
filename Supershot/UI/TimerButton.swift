//
//  TimerButton.swift
//  Supershot
//
//  Created by J on 03/08/2026.
//

import SwiftUI

struct TimerButton: View {
  
  enum TimerButtonType {
    case play
    case pause
    case skip
    
    var systemImage: String {
      switch self {
      case .play:
        return "play.fill"
      case .pause:
        return "pause.fill"
      case .skip:
        return "forward.end.fill"
      }
    }
    
    var label: String {
      switch self {
      case .play:
        return "Play"
      case .pause:
        return "Pause"
      case .skip:
        return "Skip"
      }
    }
    
    var color: Color {
      switch self {
      case .play:
        return .green
      case .pause:
        return .orange
      case .skip:
        return .gray
      }
    }
  }
  
  var type: TimerButtonType
  var action: () -> Void
  
  var body: some View {
    Button(action: action) {
      ZStack {
//        CircularProgressView(value: 60, total: 120)
        Label(type.label, systemImage: type.systemImage)
          .contentTransition(.symbolEffect)
      }
    }
    .controlSize(.extraLarge)
    .font(.largeTitle)
    .labelStyle(.iconOnly)
    .buttonStyle(.bordered)
    .buttonBorderShape(.circle)
    .tint(type.color)
  }
}

#Preview("Paused") {
  HStack {
    TimerButton(type: .skip, action: {})
    TimerButton(type: .play, action: {})
  }
}

#Preview("Active") {
  TimerButton(type: .pause, action: {})
}
