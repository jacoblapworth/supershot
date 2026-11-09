import AppSettings
import AVFAudio
import ConcurrencyExtras
import CustomDump
import Foundation
@testable import Supershot
import Testing

struct AlarmSoundTests {
  @Test(arguments: AlarmSound.allCases)
  func systemSoundIsPresentAndDecodable(sound: AlarmSound) throws {
    let url = try #require(Bundle.main.url(forResource: sound.filename, withExtension: nil))
    let audio = try AVAudioFile(forReading: url)
    let duration = Double(audio.length) / audio.fileFormat.sampleRate
    #expect(duration > 0 && duration < 30)
    #expect(audio.fileFormat.commonFormat == .pcmFormatInt16)
  }

  #if os(iOS)
    @Test func replacementsWaitForAnInFlightSchedule() async {
      let queue = AlarmOperationQueue()
      let id = UUID()
      let events = LockIsolated<[String]>([])
      let gate = AsyncStream<Void>.makeStream()
      let first = Task {
        await queue.perform(for: id) {
          events.withValue { $0.append("old starts") }
          for await _ in gate.stream {}
          events.withValue { $0.append("old ends") }
          return false
        }
      }
      while events.value.isEmpty {
        await Task.yield()
      }
      let replacement = Task {
        await queue.perform(for: id) {
          events.withValue { $0.append("replacement") }
          return false
        }
      }
      await Task.megaYield()
      expectNoDifference(events.value, ["old starts"])
      gate.continuation.finish()
      _ = await first.value
      _ = await replacement.value
      expectNoDifference(events.value, ["old starts", "old ends", "replacement"])
    }
  #endif
}
