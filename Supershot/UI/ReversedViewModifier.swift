//
//  ReversedViewModifier.swift
//  Supershot
//
//  Created by J on 16/09/2026.
//

import Foundation
import SwiftUI

struct ReversedModifier: ViewModifier {
  let reversed: Bool
  @Namespace var ns
  
  func body(content: Content) -> some View {
    Group(subviews: content) { views in
      if reversed {
        ForEach(views.reversed()) {
          $0.matchedGeometryEffect(id: $0.id, in: ns)
        }
      } else {
        ForEach(views) {
          $0.matchedGeometryEffect(id: $0.id, in: ns)
        }
      }
    }
  }
}

extension Group where Content: View {
  func reversed(_ flag: Bool = true) -> some View {
    modifier(ReversedModifier(reversed: flag))
  }
}
