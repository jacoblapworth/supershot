//
//  Sheet.swift
//  Supershot
//
//  Created by J on 13/10/2026.
//

import SwiftUI

enum SizeToFitPresentationDetent {
  case sizeToFit
}

struct SizeToFitModifier: ViewModifier {
  let additional: Set<PresentationDetent>
  @State private var contentHeight = 0.0
  
  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: { height in
        contentHeight = height
      }
      .presentationDetents(Set([.height(contentHeight)]).union(additional))
  }
}

extension View {
  
  /// Sets the sheet detent to fit its content height.
  func presentationDetents(
    _ detent: SizeToFitPresentationDetent,
    additional: Set<PresentationDetent> = []
  ) -> some View {
    modifier(SizeToFitModifier(additional: additional))
  }
}
