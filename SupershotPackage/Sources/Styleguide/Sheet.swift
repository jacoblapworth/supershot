import GameCore
import SharedModels
import SwiftUI
import WidgetSupport

//
//  Sheet.swift
//  Supershot
//
//  Created by J on 13/10/2026.
//

package enum SizeToFitPresentationDetent {
  case sizeToFit
}

package struct SizeToFitModifier: ViewModifier {
  package let additional: Set<PresentationDetent>
  @State private var contentHeight = 0.0

  package func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: { height in
        contentHeight = height
      }
      .presentationDetents(Set([.height(contentHeight)]).union(additional))
  }

  package init(additional: Set<PresentationDetent>) {
    self.additional = additional
  }
}

package extension View {
  /// Sets the sheet detent to fit its content height.
  func presentationDetents(
    _: SizeToFitPresentationDetent,
    additional: Set<PresentationDetent> = []
  ) -> some View {
    modifier(SizeToFitModifier(additional: additional))
  }
}
