import Foundation
import GameParser

@main
struct GameParserHarness {
  static func main() async {
    // Built-in acceptance inputs by default; --stdin reads an arbitrary development fixture list.
    let inputs =
      CommandLine.arguments.contains("--stdin")
        ? [String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""]
        : [GameParserDevelopmentHarness.single, GameParserDevelopmentHarness.sample]
    for text in inputs {
      let report = await GameParserDevelopmentHarness.run(text: text)
      print("Availability: \(report.availability); elapsed: \(report.elapsed)")
      switch report.result {
      case let .success(drafts): dump(drafts)
      case let .failure(error): print(error.localizedDescription)
      }
    }
  }
}
