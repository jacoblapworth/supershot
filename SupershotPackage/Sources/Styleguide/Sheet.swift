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
  @State private var presentationDetents: Set<PresentationDetent> = [.medium]
  @State private var selectedPresentationDetent: PresentationDetent = .medium


  package func body(content: Content) -> some View {
    ScrollView {
      content
        .presentationDetents(presentationDetents, selection: $selectedPresentationDetent)
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height
        } action: { height in
          contentHeight = height
          presentationDetents.insert(.height(height))
          selectedPresentationDetent = .height(height)
        }
        .transaction { transaction in
          transaction.addAnimationCompletion(criteria: .removed) {
            presentationDetents = [selectedPresentationDetent]
          }
        }
    }
    .scrollDisabled(true)
    .frame(maxWidth: .infinity, alignment: .bottom)
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
