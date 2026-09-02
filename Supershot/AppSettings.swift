import Sharing

extension SharedKey where Self == AppStorageKey<Bool>.Default {
  static var hapticsEnabled: Self {
    Self[.appStorage("hapticsEnabled"), default: true]
  }

  static var soundEffectsEnabled: Self {
    Self[.appStorage("soundEffectsEnabled"), default: true]
  }
}

extension SharedKey where Self == AppStorageKey<Int>.Default {
  static var defaultBreakDurationSeconds: Self {
    Self[.appStorage("defaultBreakDurationSeconds"), default: 60]
  }

  static var defaultPeriodDurationSeconds: Self {
    Self[.appStorage("defaultPeriodDurationSeconds"), default: 8 * 60]
  }
}
