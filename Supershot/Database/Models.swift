//
//  Models.swift
//  Supershot
//
//  Created by J on 16/09/2026.
//

import Foundation

/// Phase of a game
nonisolated enum GamePhase: Equatable, Hashable, Sendable {
  case period(number: Int, durationSeconds: Int)
  case breakTime(afterPeriod: Int, durationSeconds: Int)
  
  var durationSeconds: Int {
    switch self {
    case let .period(_, durationSeconds), let .breakTime(_, durationSeconds):
      max(durationSeconds, 0)
    }
  }
  
  var periodNumber: Int {
    switch self {
    case let .period(number, _):
      number
    case let .breakTime(afterQuarter, _):
      afterQuarter
    }
  }
  
  var isBreak: Bool {
    switch self {
    case .period: false
    case .breakTime: true
    }
  }
  
  var isQuarter: Bool { !isBreak }
}
