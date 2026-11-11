import AppSettings
import AVFAudio
import Dependencies
import Foundation
import IssueReporting

public nonisolated struct AlarmSoundPreviewClient: Sendable {
  public var play: @MainActor @Sendable (AlarmSound) -> Void
  public var stop: @MainActor @Sendable () -> Void

  public init(
    play: @escaping @MainActor @Sendable (AlarmSound) -> Void,
    stop: @escaping @MainActor @Sendable () -> Void
  ) {
    self.play = play
    self.stop = stop
  }
}

extension AlarmSoundPreviewClient: DependencyKey {
  public static var liveValue: Self {
    Self(play: { alarmPreviewPlayer.play($0) }, stop: { alarmPreviewPlayer.stop() })
  }

  public static let testValue = Self(play: { _ in }, stop: {})
  public static let previewValue = testValue
}

public extension DependencyValues {
  nonisolated var alarmSoundPreview: AlarmSoundPreviewClient {
    get { self[AlarmSoundPreviewClient.self] }
    set { self[AlarmSoundPreviewClient.self] = newValue }
  }
}

@MainActor private let alarmPreviewPlayer = AlarmSoundPreviewPlayer()

@MainActor
private final class AlarmSoundPreviewPlayer {
  private var player: AVAudioPlayer?

  func stop() {
    player?.stop()
    player = nil
  }

  func play(_ sound: AlarmSound) {
    stop()
    do {
      guard let url = Bundle.main.url(forResource: sound.filename, withExtension: nil) else {
        reportIssue("Missing bundled alarm sound: \(sound.filename)")
        return
      }
      #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
        try session.setActive(true)
      #endif
      player = try AVAudioPlayer(contentsOf: url)
      player?.play()
    } catch {
      reportIssue(error)
    }
  }
}
