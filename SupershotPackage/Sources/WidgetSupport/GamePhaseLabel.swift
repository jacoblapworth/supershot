import SharedModels
import SwiftUI

//
//  GamePhaseLabel.swift
//  SupershotWidgets
//
//  Created by J on 16/09/2026.
//

public struct GamePhaseLabel: View {
  public enum Size {
    case short
    case long
  }

  public var phase: GamePhase
  public var size: Size = .long

  private var label: String {
    switch phase {
    case .period(let period, _):
      switch size {
      case .short:
        return "Q\(period.number)"
      case .long:
        return "Quarter \(period.number)"
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

  public var body: some View {
    Text(label)
  }

  public init(phase: GamePhase, size: Size = .long) {
    self.phase = phase
    self.size = size
  }
}

#Preview {
  GamePhaseLabel(
    phase: .period(
      GamePeriodReference(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, number: 1),
      durationSeconds: 60
    )
  )
}
