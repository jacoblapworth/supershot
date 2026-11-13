//
//  LabeledContent.swift
//  SupershotPackage
//
//  Created by J on 13/11/2026.
//

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

extension LabeledContentStyle where Self == InlineLabeledContentStyle {
  public static var inline: InlineLabeledContentStyle { .init() }
}
