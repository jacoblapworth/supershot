import Foundation
import GameCore
import SharedModels
import SwiftUI
import WidgetSupport

//
//  ReversedViewModifier.swift
//  Supershot
//
//  Created by J on 16/09/2026.
//

package struct ReversedModifier: ViewModifier {
  package let reversed: Bool
  @Namespace package var ns

  package func body(content: Content) -> some View {
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

package extension Group where Content: View {
  func reversed(_ flag: Bool = true) -> some View {
    modifier(ReversedModifier(reversed: flag))
  }
}
