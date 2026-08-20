import AVFAudio
import Dependencies
import Foundation

nonisolated struct SoundEffectsClient: Sendable {
  var playGoal: @Sendable () async -> Void
}

extension DependencyValues {
  nonisolated var soundEffects: SoundEffectsClient {
    get { self[SoundEffectsClientKey.self] }
    set { self[SoundEffectsClientKey.self] = newValue }
  }
}

private nonisolated enum SoundEffectsClientKey: DependencyKey {
  static var liveValue: SoundEffectsClient {
    .live
  }

  static var previewValue: SoundEffectsClient {
    .noop
  }

  static var testValue: SoundEffectsClient {
    .noop
  }
}

nonisolated extension SoundEffectsClient {
  static let noop = Self(playGoal: {})

  static var live: Self {
    let player = SoundEffectsPlayer()
    return Self {
      await player.playGoal()
    }
  }
}

private actor SoundEffectsPlayer {
  private var goalPlayer: AVAudioPlayer?

  func playGoal() {
    #if os(iOS) || os(visionOS)
    let audioSession = AVAudioSession.sharedInstance()
    try? audioSession.setCategory(.ambient, mode: .default, options: .mixWithOthers)
    try? audioSession.setActive(true)
    #endif

    if goalPlayer == nil {
      guard let url = Bundle.main.url(forResource: "success_blip", withExtension: "mp3") else {
        return
      }
      goalPlayer = try? AVAudioPlayer(contentsOf: url)
      goalPlayer?.prepareToPlay()
    }

    goalPlayer?.currentTime = 0
    goalPlayer?.play()
  }
}
