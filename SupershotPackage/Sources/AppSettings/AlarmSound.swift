import Foundation
import Sharing

/// One app-wide sound for quarter-end and break-end alarms.
public nonisolated enum AlarmSound: String, CaseIterable, Identifiable, Sendable {
  case buzzer
  case whistle
  case airHorn
  case softChime
  case electronicPulse

  public var id: Self {
    self
  }

  public var title: LocalizedStringResource {
    switch self {
    case .buzzer: "Buzzer"
    case .whistle: "Whistle"
    case .airHorn: "Air horn"
    case .softChime: "Soft chime"
    case .electronicPulse: "Electronic pulse"
    }
  }

  /// Files live in the app's main bundle so system alarm services can resolve them.
  public var filename: String {
    "alarm-\(rawValue).caf"
  }
}

public extension SharedKey where Self == AppStorageKey<AlarmSound>.Default {
  nonisolated static var alarmSound: Self {
    Self[.appStorage("alarmSound"), default: .buzzer]
  }
}
