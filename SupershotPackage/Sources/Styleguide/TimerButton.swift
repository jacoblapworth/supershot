import GameCore
import SharedModels
import SwiftUI
import WidgetSupport

//
//  TimerButton.swift
//  Supershot
//
//  Created by J on 03/08/2026.
//

package struct TimerButton: View {

  package enum TimerButtonType {
    case play
    case pause
    case skip

    package var systemImage: String {
      switch self {
      case .play:
        return "play.fill"
      case .pause:
        return "pause.fill"
      case .skip:
        return "forward.end.fill"
      }
    }

    package var label: String {
      switch self {
      case .play:
        return "Play"
      case .pause:
        return "Pause"
      case .skip:
        return "Skip"
      }
    }

    package var color: Color {
      switch self {
      case .play:
        return .green
      case .pause:
        return .orange
      case .skip:
        return Color(hex: "#F14848")
      }
    }
  }

  package var type: TimerButtonType
  package var action: () -> Void

  package var body: some View {
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

  package init(type: TimerButtonType, action: @escaping () -> Void) {
    self.type = type
    self.action = action
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
