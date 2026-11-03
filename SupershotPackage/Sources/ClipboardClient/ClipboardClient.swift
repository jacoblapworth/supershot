import Dependencies
#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

package nonisolated struct ClipboardClient: Sendable {
  package var paste: @MainActor @Sendable () -> String?
}

package extension ClipboardClient {
  static var live: Self {
    .init(paste: {
      #if canImport(UIKit)
        UIPasteboard.general.string
      #elseif canImport(AppKit)
        NSPasteboard.general.string(forType: .string)
      #else
        nil
      #endif
    })
  }

  static var test: Self {
    .init(paste: unimplemented("ClipboardClient.paste"))
  }

  static func constant(_ value: @MainActor @Sendable @autoclosure @escaping () -> String?) -> Self {
    .init(paste: value)
  }
}

extension ClipboardClient: DependencyKey {
  package static let liveValue = Self.live
  package static let testValue = Self.test
}

package extension DependencyValues {
  nonisolated var clipboard: ClipboardClient {
    get { self[ClipboardClient.self] }
    set { self[ClipboardClient.self] = newValue }
  }
}
