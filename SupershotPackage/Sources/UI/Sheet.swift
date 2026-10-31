import SwiftUI

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

#Preview("Sheet fitted to content") {
  @Previewable @State var isPresented = true
  @Previewable @State var showsDetails = false

  Button("Show sheet") { isPresented = true }
    .sheet(isPresented: $isPresented) {
      VStack(alignment: .leading, spacing: 16) {
        Text("Game summary").font(.headline)
        Toggle("Show details", isOn: $showsDetails)
        if showsDetails {
          Text("Silver Ferns versus Diamonds")
          Text("Four 15-minute quarters")
        }
        Button("Done") { isPresented = false }
      }
      .padding(24)
      .presentationDetents(.sizeToFit)
    }
}
