import GameCore
import Sharing

extension SharedKey where Self == AppStorageKey<Bool>.Default {
  static public var hasCompletedWelcome: Self {
    Self[.appStorage("hasCompletedWelcome"), default: false]
  }

  static public var hapticsEnabled: Self {
    Self[.appStorage("hapticsEnabled"), default: true]
  }

  static public var soundEffectsEnabled: Self {
    Self[.appStorage("soundEffectsEnabled"), default: true]
  }
}

extension SharedKey where Self == AppStorageKey<Int>.Default {
  static public var defaultBreakDurationSeconds: Self {
    Self[.appStorage("defaultBreakDurationSeconds"), default: 60]
  }

  static public var defaultPeriodDurationSeconds: Self {
    Self[.appStorage("defaultPeriodDurationSeconds"), default: 8 * 60]
  }
}

extension SharedKey where Self == AppStorageKey<BreakStartPolicy>.Default {
  static public var defaultBreakStartPolicy: Self {
    Self[.appStorage("defaultBreakStartPolicy"), default: .automatic]
  }
}
