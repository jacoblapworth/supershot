import Foundation
import OSLog

/// Public diagnostics contain only structure and failure categories, never pasted fixture text.
nonisolated enum GameParserDiagnostics {
  static let logger = Logger(subsystem: "Supershot", category: "GameParser")
  @TaskLocal static var requestID = "none"
}
