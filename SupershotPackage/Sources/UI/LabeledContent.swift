import SwiftUI

public struct InlineLabeledContentStyle: LabeledContentStyle {
  public func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline) {
      configuration.label
        .foregroundStyle(.secondary)
      configuration.content
    }
  }
}

public extension LabeledContentStyle where Self == InlineLabeledContentStyle {
  static var inline: InlineLabeledContentStyle {
    .init()
  }
}
